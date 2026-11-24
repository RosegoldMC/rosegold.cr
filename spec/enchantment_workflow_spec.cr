require "./spec_helper"

class Rosegold::EnchantmentWorkflowSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def connection_for_test=(connection : Rosegold::Connection::Client)
    @connection = connection
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    super
    @sent_packets << packet
  end

  def send_packet_if!(packet : GuardedPacket, session : PlaySession? = nil, &guard : -> Bool) : Bool
    sent = super(packet, session, &guard)
    @sent_packets << packet if sent
    sent
  end

  def sent_hand_tap_for_test(hand : Rosegold::Hand? = :main_hand)
    interactions.tap_using_hand hand
    tick_inputs_for_test
  end

  def tick_inputs_for_test
    interactions.tick
  end

  def hand_tap_sequence_for_test
    interactions.last_hand_tap_sequence
  end

  def physics_for_test
    physics
  end
end

class CancelledOpeningSpecBot < Rosegold::Bot
  def initialize(@opening_client : Rosegold::EnchantmentWorkflowSpecClient)
    super(@opening_client)
  end

  def use_hand(target : Rosegold::Vec3d? | Rosegold::Look? = nil, hand : Rosegold::Hand? = nil)
    raise "enchanting must pin the main hand" unless hand == Rosegold::Hand::MainHand
    @opening_client.sent_hand_tap_for_test hand
  end
end

Spectator.describe Rosegold::EnchantmentWorkflow do
  def opening_client
    client = Rosegold::EnchantmentWorkflowSpecClient.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "openingtest"})
    connection = Rosegold::Connection::Client.new(Minecraft::IO::Memory.new,
      Rosegold::ProtocolState::PLAY, Rosegold::Client.protocol_version, client)
    client.connection_for_test = connection
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    dimension = client.dimension_for_test
    chunk_data = Minecraft::IO::Memory.new
    (dimension.world_height >> 4).times { Rosegold::Section.empty.write(chunk_data) }
    dimension.load_chunk(Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(chunk_data.to_slice), dimension))
    table = Rosegold::MCData.default.blocks.find! { |block| block.id_str == "enchanting_table" }
    dimension.set_block_state(Rosegold::Vec3i.new(0, 0, 2), table.min_state_id)
    client.player.feet = Rosegold::Vec3d.new(0.5, 0.5 - Rosegold::Player::DEFAULT_EYE_HEIGHT, 0.5)
    client.player.look = Rosegold::Look::SOUTH
    client
  end

  def temporary_opening_handlers(client)
    {Rosegold::Event::ContainerOpened, Rosegold::Clientbound::SetContainerContent,
     Rosegold::Clientbound::AcknowledgeBlockChange, Rosegold::Event::Disconnected}.map do |type|
      client.event_handlers[type]?.try(&.size) || 0
    end
  end

  def timeout_opening(bot)
    expect { bot.enchant("book", option: 0, timeout: 5.milliseconds) }
      .to raise_error(Exception, /Timed out while enchanting/)
  end

  def acknowledge(client, sequence)
    packet = Rosegold::Clientbound::AcknowledgeBlockChange.new(sequence)
    packet.callback(client)
    client.emit_event(packet)
  end

  it "closes a table that arrives after timeout and releases the pending opening" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    other_bot = Rosegold::Bot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    expect { other_bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)

    Rosegold::Clientbound::OpenWindow.new(4_u32, 13_u32, Rosegold::Chat.new("Enchant")).callback(client)

    expect(client.container_menu).to be(client.inventory_menu)
    expect(client.sent_packets.last.as(Rosegold::Serverbound::CloseWindow).window_id).to eq(4_u16)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    timeout_opening(bot)
    acknowledge(client, client.sequence_counter)
  end

  it "ignores stale acknowledgements and accepts a cumulative acknowledgement as the opening barrier" do
    client = opening_client
    client.next_sequence
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    acknowledge(client, client.hand_tap_sequence_for_test - 1)
    expect { bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)

    acknowledge(client, client.sequence_counter + 1)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    Rosegold::Clientbound::OpenWindow.new(8_u32, 13_u32, Rosegold::Chat.new("Later")).callback(client)
    expect(client.container_menu.id).to eq(8_u8)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end

  it "does not close an unrelated or replaced menu while waiting for the cancelled response" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    replacement = Rosegold::ChestMenu.new(client, 8_u8, Rosegold::Chat.new("Other"), rows: 1)
    client.container_menu = replacement
    client.emit_event Rosegold::Event::ContainerOpened.new(0_u32, "Other", replacement)
    stale = Rosegold::EnchantmentMenu.new(client, 4_u8, Rosegold::Chat.new("Enchant"))
    client.emit_event Rosegold::Event::ContainerOpened.new(13_u32, "Enchant", stale)

    expect(client.container_menu).to be(replacement)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
    acknowledge(client, client.sequence_counter)
    expect(temporary_opening_handlers(client)).to eq(handlers)
  end

  it "cleans up a cancelled request on disconnect without closing a later connection's menu" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    client.disconnect("test disconnect")
    expect(temporary_opening_handlers(client)).to eq(handlers)

    replacement = Rosegold::EnchantmentMenu.new(client, 8_u8, Rosegold::Chat.new("Later"))
    client.container_menu = replacement
    client.emit_event Rosegold::Event::ContainerOpened.new(13_u32, "Later", replacement)
    expect(client.container_menu).to be(replacement)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end

  it "cancels an unsent tap without retaining late-opening listeners" do
    client = opening_client
    bot = Rosegold::Bot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)

    client.tick_inputs_for_test
    expect(client.sequence_counter).to eq(0)
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerBlockPlacement)).to be_empty
    expect(temporary_opening_handlers(client)).to eq(handlers)
    Rosegold::Clientbound::OpenWindow.new(8_u32, 13_u32, Rosegold::Chat.new("Later")).callback(client)
    expect(client.container_menu.id).to eq(8_u8)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end

  def hand_back(client)
    client.manual_control.revoke Rosegold::ManualControl::Reason::Returned
    client.physics_for_test.unpause_for_spawn_chunk
    client.manual_control.before_tick
    client.manual_control.after_tick
    client.physics_for_test.pause
  end

  def open_table(client, id : UInt32, title = "Enchant")
    Rosegold::Clientbound::OpenWindow.new(id, 13_u32, Rosegold::Chat.new(title)).callback(client)
    client.emit_event Rosegold::Clientbound::SetContainerContent.new(id, 1_u32,
      [] of Rosegold::WindowSlot, Rosegold::WindowSlot.new(-1, Rosegold::Slot.new))
    client.container_menu
  end

  def enchanting(bot) : Channel(Exception?)
    done = Channel(Exception?).new(1)
    spawn do
      bot.enchant("book", option: 0, timeout: 1.second)
      done.send nil
    rescue error
      done.send error
    end
    Fiber.yield
    done
  end

  def closes(client) : Int32
    client.sent_packets.count(&.is_a?(Rosegold::Serverbound::CloseWindow))
  end

  it "neither claims nor closes a menu the operator opens after a grant, during it or after handback" do
    {false, true}.each do |after_handback|
      client = opening_client
      bot = CancelledOpeningSpecBot.new(client)
      done = enchanting(bot)
      client.manual_control.grant || fail("grant refused")
      hand_back client if after_handback
      operator = open_table(client, 5_u32, "Operator")
      hand_back client unless after_handback
      error = done.receive
      expect(error.try(&.message)).to match(/interrupted the enchantment/)
      expect(closes(client)).to eq 0
      expect(client.container_menu).to be(operator)
      acknowledge(client, client.sequence_counter)
    end
  end

  it "leaves a late table to a controller that took input after the request was cancelled" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    timeout_opening(bot)
    client.manual_control.grant || fail("grant refused")
    late = open_table(client, 4_u32)
    expect(client.container_menu).to be(late)
    expect(closes(client)).to eq 0
    acknowledge(client, client.sequence_counter)
    expect(closes(client)).to eq 0
  end

  it "leaves its own table to a controller that holds input when the wait fails" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    done = enchanting(bot)
    Rosegold::Clientbound::OpenWindow.new(4_u32, 13_u32, Rosegold::Chat.new("Enchant")).callback(client)
    table = client.container_menu
    client.manual_control.grant || fail("grant refused")
    expect(done.receive.try(&.message)).to match(/interrupted the enchantment/)
    expect(closes(client)).to eq 0
    expect(client.container_menu).to be(table)
  end

  it "closes its own table when the run fails with no controller holding input" do
    {false, true}.each do |handed_back|
      client = opening_client
      bot = CancelledOpeningSpecBot.new(client)
      done = enchanting(bot)
      if handed_back
        Rosegold::Clientbound::OpenWindow.new(4_u32, 13_u32, Rosegold::Chat.new("Enchant")).callback(client)
        client.manual_control.grant || fail("grant refused")
        hand_back client
        expect(done.receive.try(&.message)).to match(/interrupted the enchantment/)
      else
        open_table(client, 4_u32)
        expect(done.receive.try(&.message)).to match(/No matching item/)
      end
      expect(closes(client)).to eq 1
      expect(client.container_menu).to be(client.inventory_menu)
    end
  end

  it "retires a cancelled opening when configuration ends its PLAY session, closing nothing" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    expect { bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)

    Rosegold::Clientbound::StartConfiguration.new.callback(client)
    expect(client.current_protocol_state).to eq Rosegold::ProtocolState::CONFIGURATION
    client.set_protocol_state(Rosegold::ProtocolState::PLAY)
    expect(temporary_opening_handlers(client)).to eq(handlers)

    late = open_table(client, 4_u32, "Later")
    expect(client.container_menu).to be(late)
    expect(closes(client)).to eq 0

    late.handle_close
    timeout_opening(bot)
    acknowledge(client, client.sequence_counter)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    expect(closes(client)).to eq 0
  end

  it "keeps the acknowledgement barrier for a cancelled opening across a respawn in the same session" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    client.reset_mining_session
    expect { bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)
    expect(temporary_opening_handlers(client)).not_to eq(handlers)
    acknowledge(client, client.sequence_counter)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    expect(closes(client)).to eq 0
  end

  it "admits one enchant per client across wrappers and leaves the entrant's request intact" do
    client = opening_client
    first = CancelledOpeningSpecBot.new(client)
    others = {CancelledOpeningSpecBot.new(client), Rosegold::Bot.new(client)}
    retry_bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    done = Channel(Exception?).new(1)
    spawn do
      first.enchant("book", option: 0, timeout: 100.milliseconds)
      done.send nil
    rescue error
      done.send error
    end
    Fiber.yield
    in_flight = temporary_opening_handlers(client)
    sequence = client.sequence_counter
    expect(sequence).to be > 0

    others.each do |other|
      expect { other.enchant("book", option: 0) }
        .to raise_error(Exception, "An enchantment operation is already in progress")
    end
    expect(temporary_opening_handlers(client)).to eq(in_flight)
    expect(client.sequence_counter).to eq(sequence)

    expect(done.receive.try(&.message)).to match(/Timed out while enchanting/)
    expect { retry_bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)
    acknowledge(client, sequence)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    expect(closes(client)).to eq 0
  end

  it "does not let a stale acknowledgement settle a newer request from another wrapper" do
    client = opening_client
    older_bot = CancelledOpeningSpecBot.new(client)
    newer_bot = CancelledOpeningSpecBot.new(client)
    plain_bot = Rosegold::Bot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(older_bot)
    older = client.sequence_counter
    acknowledge(client, older)
    expect(temporary_opening_handlers(client)).to eq(handlers)

    timeout_opening(newer_bot)
    newer = client.sequence_counter
    expect(newer).to be > older
    acknowledge(client, older)
    expect { newer_bot.enchant("book", option: 0) }
      .to raise_error(Exception, /cancelled enchantment table opening is still pending/)
    expect(temporary_opening_handlers(client)).not_to eq(handlers)

    acknowledge(client, newer)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    timeout_opening(plain_bot)
    expect(temporary_opening_handlers(client)).to eq(handlers)
  end

  it "settles on the table-use acknowledgement without a hand-release packet" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    client.tick_inputs_for_test
    placement = client.sent_packets.select(Rosegold::Serverbound::PlayerBlockPlacement).first
    expect(placement.location).to eq(Rosegold::Vec3i.new(0, 0, 2))
    expect(placement.sequence).to eq(client.hand_tap_sequence_for_test)
    expect(placement.sequence).to eq(client.sequence_counter)
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty

    acknowledge(client, placement.sequence)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    Rosegold::Clientbound::OpenWindow.new(8_u32, 13_u32, Rosegold::Chat.new("Later")).callback(client)
    expect(client.container_menu.id).to eq(8_u8)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end
end
