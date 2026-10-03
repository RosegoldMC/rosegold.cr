require "./spec_helper"

class EnchantingSpecClient < Rosegold::Client
  def connection_for_test=(connection : Rosegold::Connection::Client)
    @connection = connection
  end
end

class EnchantingOpeningRaceBot < Rosegold::Bot
  def initialize(@race_client : EnchantingSpecClient, @opening_menu : Rosegold::EnchantmentMenu)
    super(@race_client)
  end

  def use_hand(target : Rosegold::Vec3d? | Rosegold::Look? = nil, hand : Rosegold::Hand = :main_hand)
    @race_client.container_menu = @opening_menu
    @race_client.emit_event Rosegold::Event::ContainerOpened.new(13_u32, "Enchant", @opening_menu)
    packet = Rosegold::Clientbound::SetContainerContent.new(
      @opening_menu.id.to_u32,
      1_u32,
      @opening_menu.slots,
      Rosegold::WindowSlot.new(-1, Rosegold::Slot.new)
    )
    packet.callback(@race_client)
    @race_client.emit_event(packet)
  end
end

Spectator.describe Rosegold::EnchantmentMenu do
  def prepared_menu
    io = Minecraft::IO::Memory.new
    connection = Rosegold::Connection::Client.new(io, Rosegold::ProtocolState::PLAY, Rosegold::Client.protocol_version)
    client = EnchantingSpecClient.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "enchantingtest"})
    client.connection_for_test = connection
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    client.player.experience_level = 30_u32
    menu = Rosegold::EnchantmentMenu.new(client, 4_u8, Rosegold::Chat.new("Enchant"))
    client.container_menu = menu
    menu[0] = Rosegold::Slot.new(count: 1_u32, item_id_int: 1_u32)
    menu[1] = Rosegold::Slot.new(count: 3_u32, item_id_int: Rosegold::MCData.default.items.find! { |item| item.name == "lapis_lazuli" }.id)
    menu.properties[0_i16] = 1_i16
    menu.properties[4_i16] = 0_i16
    menu.properties[7_i16] = 1_i16
    {client, menu, io}
  end

  def deliver(client, packet)
    packet.callback(client)
    client.emit_event(packet)
  end

  def enchanted(item_id : UInt32)
    components = Hash(String, Rosegold::DataComponent){
      "enchantments" => Rosegold::DataComponents::Enchantments.new({1_u32 => 1_u32}),
    }
    Rosegold::Slot.new(1_u32, item_id, components, Set(String).new)
  end

  def stored_enchanted_book
    book_id = Rosegold::MCData.default.items.find! { |item| item.name == "enchanted_book" }.id
    components = Hash(String, Rosegold::DataComponent){
      "stored_enchantments" => Rosegold::DataComponents::Enchantments.new({1_u32 => 1_u32}),
    }
    Rosegold::Slot.new(1_u32, book_id, components, Set(String).new)
  end

  def handler_count(client, event_type)
    client.event_handlers[event_type]?.try(&.size) || 0
  end

  it "rejects invalid selections and non-positive timeouts before sending a button click" do
    _, menu, io = prepared_menu

    expect { menu.enchant(-1, 10.milliseconds) }.to raise_error(ArgumentError, /between 0 and 2/)
    expect { menu.enchant(3, 10.milliseconds) }.to raise_error(ArgumentError, /between 0 and 2/)
    expect { menu.enchant(0, Time::Span.zero) }.to raise_error(ArgumentError, /timeout must be positive/)
    expect(io.size).to eq(0)
  end

  it "requires an advertised option rather than clicking a server-withdrawn offer" do
    _, menu, io = prepared_menu
    menu.properties[0_i16] = 0_i16

    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /not available/)
    expect(io.size).to eq(0)
  end

  it "rejects a closed or replaced menu before sending an action" do
    client, menu, io = prepared_menu
    client.container_menu = client.inventory_menu

    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /no longer active/)
    expect(io.size).to eq(0)

    replacement = Rosegold::ChestMenu.new(client, 8_u8, Rosegold::Chat.new("Other"), rows: 1)
    client.container_menu = replacement
    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /no longer active/)
    expect(io.size).to eq(0)
  end

  it "does not miss initial content sent synchronously while the bot opens the table" do
    client, menu, _ = prepared_menu
    client.container_menu = client.inventory_menu
    bot = EnchantingOpeningRaceBot.new(client, menu)

    expect { bot.enchant("diamond_pickaxe", option: 0, timeout: 20.milliseconds) }
      .to raise_error(Exception, /No matching item available to enchant/)
  end

  it "waits for matching enchanted input, lapis, and experience updates" do
    client, menu, _ = prepared_menu
    original_handlers = handler_count(client, Rosegold::Clientbound::SetSlot)

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(7_i8, 1_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
      deliver client, Rosegold::Clientbound::SetExperience.new(0_f32, 29_u32, 0_u32)
    end

    result = menu.enchant(0, 100.milliseconds)

    expect(result.enchanted?).to be_true
    expect(handler_count(client, Rosegold::Clientbound::SetSlot)).to eq(original_handlers)
  end

  it "does not treat local prediction or unrelated packets as a result and cleans listeners on timeout" do
    client, menu, _ = prepared_menu
    original_slot_handlers = handler_count(client, Rosegold::Clientbound::SetSlot)
    original_content_handlers = handler_count(client, Rosegold::Clientbound::SetContainerContent)
    original_experience_handlers = handler_count(client, Rosegold::Clientbound::SetExperience)

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(7_i8, 1_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, menu[0]))
    end

    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /Timed out waiting for enchantment confirmation/)
    expect(handler_count(client, Rosegold::Clientbound::SetSlot)).to eq(original_slot_handlers)
    expect(handler_count(client, Rosegold::Clientbound::SetContainerContent)).to eq(original_content_handlers)
    expect(handler_count(client, Rosegold::Clientbound::SetExperience)).to eq(original_experience_handlers)
  end

  it "accepts an identical raw XP packet without an experience-changed event" do
    client, menu, _ = prepared_menu
    experience_changed = false
    listener = client.on(Rosegold::Event::ExperienceChanged) { experience_changed = true }

    begin
      spawn do
        sleep 2.milliseconds
        deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
        deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
        deliver client, Rosegold::Clientbound::SetExperience.new(0_f32, 30_u32, 0_u32)
      end

      expect(menu.enchant(0, 100.milliseconds).enchanted?).to be_true
      expect(experience_changed).to be_false
    ensure
      client.off(Rosegold::Event::ExperienceChanged, listener)
    end
  end

  it "accepts an XP update before inventory confirmation when concurrent gains preserve the level" do
    client, menu, _ = prepared_menu

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetExperience.new(0.5_f32, 30_u32, 1_u32)
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
    end

    expect(menu.enchant(0, 100.milliseconds).enchanted?).to be_true
  end

  it "times out after matching item and lapis confirmation without an XP packet" do
    client, menu, _ = prepared_menu
    original_experience_handlers = handler_count(client, Rosegold::Clientbound::SetExperience)

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
    end

    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /Timed out waiting for enchantment confirmation/)
    expect(handler_count(client, Rosegold::Clientbound::SetExperience)).to eq(original_experience_handlers)
  end

  it "requires an XP packet for creative enchantments with experience levels" do
    client, menu, _ = prepared_menu
    client.player.gamemode = 1_i8

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
    end

    expect { menu.enchant(0, 10.milliseconds) }.to raise_error(Exception, /Timed out waiting for enchantment confirmation/)
  end

  it "does not require an XP packet for creative enchantments at level zero" do
    client, menu, _ = prepared_menu
    client.player.gamemode = 1_i8
    client.player.experience_level = 0_u32

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(1_u32)))
    end

    expect(menu.enchant(0, 100.milliseconds).enchanted?).to be_true
  end

  it "does not confirm an enchanted item with the wrong identity" do
    client, menu, _ = prepared_menu

    spawn do
      sleep 2.milliseconds
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, enchanted(2_u32)))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
      deliver client, Rosegold::Clientbound::SetExperience.new(0_f32, 29_u32, 0_u32)
    end

    expect { menu.enchant(0, 20.milliseconds) }.to raise_error(Exception, /Timed out waiting for enchantment confirmation/)
  end

  it "returns a detached stored-enchantments snapshot when a book becomes an enchanted book" do
    client, menu, _ = prepared_menu
    book_id = Rosegold::MCData.default.items.find! { |item| item.name == "book" }.id
    menu[0] = Rosegold::Slot.new(count: 1_u32, item_id_int: book_id)

    spawn do
      sleep 2.milliseconds
      result = stored_enchanted_book
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(0, result))
      deliver client, Rosegold::Clientbound::SetSlot.new(4_i8, 2_u32, Rosegold::WindowSlot.new(1, Rosegold::Slot.new(count: 2_u32, item_id_int: menu[1].item_id_int)))
      deliver client, Rosegold::Clientbound::SetExperience.new(0_f32, 29_u32, 0_u32)
      menu[0] = Rosegold::Slot.new
    end

    result = menu.enchant(0, 100.milliseconds)
    expect(result.name).to eq("enchanted_book")
    expect(result.stored_enchantments.empty?).to be_false
    expect(menu.item.empty?).to be_true
  end

  it "stops waiting when the active menu is replaced during confirmation" do
    client, menu, _ = prepared_menu
    original_slot_handlers = handler_count(client, Rosegold::Clientbound::SetSlot)

    spawn do
      sleep 2.milliseconds
      client.container_menu = Rosegold::ChestMenu.new(client, 8_u8, Rosegold::Chat.new("Other"), rows: 1)
    end

    expect { menu.enchant(0, 100.milliseconds) }.to raise_error(Exception, /no longer active/)
    expect(handler_count(client, Rosegold::Clientbound::SetSlot)).to eq(original_slot_handlers)
  end

  it "fails promptly on disconnect and removes temporary listeners" do
    client, menu, _ = prepared_menu
    original_slot_handlers = handler_count(client, Rosegold::Clientbound::SetSlot)

    spawn do
      sleep 2.milliseconds
      client.connection.disconnect("test disconnect")
    end

    expect { menu.enchant(0, 100.milliseconds) }.to raise_error(Rosegold::Client::NotConnected, /Disconnected while enchanting/)
    expect(handler_count(client, Rosegold::Clientbound::SetSlot)).to eq(original_slot_handlers)
  end

  it "rejects an overlapping selection while the first confirmation is pending" do
    _, menu, _ = prepared_menu
    overlap_error = nil

    spawn do
      sleep 2.milliseconds
      begin
        menu.enchant(0, 10.milliseconds)
      rescue ex
        overlap_error = ex
      end
    end

    expect { menu.enchant(0, 30.milliseconds) }.to raise_error(Exception, /Timed out waiting for enchantment confirmation/)
    expect(overlap_error.try(&.message)).to eq("An enchantment operation is already in progress")
  end
end
