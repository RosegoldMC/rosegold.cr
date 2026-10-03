require "./spec_helper"

class Rosegold::Interactions
  def queued_hand_tap_for_test?
    !@queued_hand_tap.nil?
  end
end

class Rosegold::EnchantmentWorkflowSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet

  def connection_for_test=(connection : Rosegold::Connection::Client)
    @connection = connection
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    super
    @sent_packets << packet
  end

  def sent_hand_tap_for_test
    interactions.tap_using_hand
    interactions.tick
  end

  def hand_tap_sequence_for_test
    interactions.last_hand_tap_sequence
  end

  def queued_hand_tap_for_test?
    interactions.queued_hand_tap_for_test?
  end
end

class CancelledOpeningSpecBot < Rosegold::Bot
  def initialize(@opening_client : Rosegold::EnchantmentWorkflowSpecClient)
    super(@opening_client)
  end

  def use_hand(target : Rosegold::Vec3d? | Rosegold::Look? = nil, hand : Rosegold::Hand = :main_hand)
    @opening_client.sent_hand_tap_for_test
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

    expect(client.sequence_counter).to eq(0)
    expect(client.queued_hand_tap_for_test?).to be_false
    expect(temporary_opening_handlers(client)).to eq(handlers)
    Rosegold::Clientbound::OpenWindow.new(8_u32, 13_u32, Rosegold::Chat.new("Later")).callback(client)
    expect(client.container_menu.id).to eq(8_u8)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end

  it "settles on the use acknowledgement without waiting for an unacknowledged hand release" do
    client = opening_client
    bot = CancelledOpeningSpecBot.new(client)
    handlers = temporary_opening_handlers(client)
    timeout_opening(bot)
    release = client.sent_packets.last.as(Rosegold::Serverbound::PlayerAction)
    expect(release.sequence).to be > client.hand_tap_sequence_for_test

    acknowledge(client, client.hand_tap_sequence_for_test)
    expect(temporary_opening_handlers(client)).to eq(handlers)
    Rosegold::Clientbound::OpenWindow.new(8_u32, 13_u32, Rosegold::Chat.new("Later")).callback(client)
    expect(client.container_menu.id).to eq(8_u8)
    expect(client.sent_packets.any?(Rosegold::Serverbound::CloseWindow)).to be_false
  end
end
