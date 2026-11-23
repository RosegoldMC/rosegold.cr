require "../spec_helper"

class ItemCooldownSpecClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet
  property on_send : Proc(Rosegold::Serverbound::Packet, Nil)? = nil

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
    on_send.try &.call(packet)
  end

  def input
    interactions
  end

  def ready=(ready : Bool)
    physics.paused = !ready
  end

  def frame
    tick_frame
  end

  def attach_transport(transport : Minecraft::IO::Memory)
    @connection = Rosegold::Connection::Client.new(transport, current_protocol_state, protocol_version, self)
  end

  def read_next_packet
    read_packet
  end
end

Spectator.describe "Server-backed item cooldowns" do
  alias Hand = Rosegold::Hand
  alias Cooldown = Rosegold::DataComponents::UseCooldown

  let(bot_client) { ItemCooldownSpecClient.new("localhost") }
  let(input) { bot_client.input }
  let(main) { Hand::MainHand }
  let(off) { Hand::OffHand }

  before_each do
    bot_client.current_protocol_state = Rosegold::ProtocolState::PLAY
    bot_client.ready = true
    hold("apple")
    hold("stone", off)
    bot_client.player.food = 10_u32
  end

  def hold(name : String, hand : Hand = Hand::MainHand)
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == name }
    Rosegold::Slot.new(1_u32, item.id).tap do |slot|
      bot_client.inventory_menu[hand.main_hand? ? 36 : 45] = slot
    end
  end

  def cooldown(group = "minecraft:apple", duration = 1)
    Rosegold::Clientbound::SetCooldown.new(group, duration).callback(bot_client)
  end

  def attach_cooldown_frame
    packet = Rosegold::Clientbound::SetCooldown.new("minecraft:apple", 30).write
    transport = Minecraft::IO::Memory.new
    transport.write packet.size.to_u32
    transport.write packet
    transport.rewind
    bot_client.attach_transport(transport)
  end

  def tap(hand : Hand? = nil)
    input.tap_using_hand(hand)
    bot_client.frame
  end

  def use_packets
    bot_client.sent_packets.select(Rosegold::Serverbound::UseItem)
  end

  def hands
    use_packets.map(&.hand)
  end

  it "still sends sequenced use for a cooled item, then tries the off hand without predicting consumption" do
    cooldown
    tap

    expect(hands).to eq([main, off])
    expect(use_packets.map(&.sequence)).to eq([1, 2])
    expect(bot_client.pending_block_operations[2].operation_type).to eq(:use)
    expect(input.last_hand_tap_sequence).to eq(2)
    expect(input.use_release_pending?).to be_false

    tap

    expect(hands).to eq([main, off, main])
    expect(input.use_release_pending?).to be_true
  end

  it "replaces an active duration with the last update for that group before input" do
    cooldown(duration: 30)
    bot_client.frame
    cooldown(duration: 4)
    cooldown("apple", duration: 1)

    tap
    tap

    expect(hands).to eq([main, off, main])
    expect(input.use_release_pending?).to be_true
  end

  it "clears the active group before input for a zero duration" do
    cooldown(duration: 30)
    bot_client.frame
    cooldown(duration: 0)
    tap

    expect(hands).to eq([main])
    expect(input.use_release_pending?).to be_true
  end

  sample [-1, Int32::MIN] do |duration|
    it "replaces an active cooldown with one input frame for a negative duration" do
      cooldown(duration: 30)
      bot_client.frame
      cooldown(duration: duration)
      tap
      expect(hands).to eq([main, off])
      expect(input.use_release_pending?).to be_false

      tap
      expect(hands).to eq([main, off, main])
      expect(input.use_release_pending?).to be_true
    end
  end

  it "uses a patched group shared by two different known items instead of their stock names" do
    group = Cooldown.new(99.0_f32, true, "test:shared")
    hold("apple").components_to_add["use_cooldown"] = group
    cooldown
    tap
    expect(hands).to eq([main])

    cooldown("test:shared", duration: 2)
    tap
    hold("shield").components_to_add["use_cooldown"] = group
    tap

    expect(hands).to eq([main, main, off, main, off])
    expect(input.use_release_pending?).to be_false
  end

  sample [{"minecraft:", ""}, {"", ":"}, {"test:", "test:"}] do |groups|
    it "matches an explicit cooldown group with an empty path" do
      packet_group, slot_group = groups
      hold("apple").components_to_add["use_cooldown"] = Cooldown.new(1.0_f32, true, slot_group)
      cooldown(packet_group)
      tap

      expect(hands).to eq([main, off])
      expect(input.use_release_pending?).to be_false
    end
  end

  sample [false, true] do |removed|
    it "uses the stock key when the cooldown component has no group or was removed" do
      slot = hold("ender_pearl")
      if removed
        slot.components_to_remove.add("use_cooldown")
      else
        slot.components_to_add["use_cooldown"] = Cooldown.new(99.0_f32)
      end

      cooldown("minecraft:ender_pearl")
      tap
      tap

      expect(hands).to eq([main, off, main])
    end
  end

  it "does not assume a pass for an unknown item even with an explicit matching group" do
    slot = Rosegold::Slot.new(1_u32, 999_999_u32)
    slot.components_to_add["use_cooldown"] = Cooldown.new(1.0_f32, true, "test:shared")
    bot_client.inventory_menu[36] = slot
    cooldown("test:shared")
    tap

    expect(hands).to eq([main])
  end

  sample [
    Rosegold::DataComponents::Damage.new(1_u32),
    Cooldown.new(1.0_f32, true, "bad group"),
    Cooldown.new(1.0_f32, true, String.new(Bytes[0xff])),
    Cooldown.new(1.0_f32, true),
  ] do |patch|
    it "does not fall back to the stock group for an invalid cooldown patch" do
      slot = hold("apple")
      slot.components_to_add["use_cooldown"] = patch
      cooldown
      tap

      expect(hands).to eq([main])
    end
  end

  it "waits for readiness, then advances the timer on each stepped input frame" do
    bot_client.ready = false
    bot_client.update_ticking_state(20.0_f32, true)
    cooldown
    input.tap_using_hand(nil)
    2.times { bot_client.frame }
    expect(use_packets).to be_empty

    bot_client.ready = true
    bot_client.add_tick_steps(2_u32)
    bot_client.frame
    tap

    expect(hands).to eq([main, off, main])
    expect(bot_client.sent_packets.count(&.is_a?(Rosegold::Serverbound::ClientTickEnd))).to eq(2)
  end

  it "ages loaded timers on frozen pulses without processing input, even if physics pauses" do
    bot_client.frame
    bot_client.ready = false
    bot_client.update_ticking_state(20.0_f32, true)
    cooldown
    tap
    expect(use_packets).to be_empty
    expect(bot_client.sent_packets.count(&.is_a?(Rosegold::Serverbound::ClientTickEnd))).to eq(1)

    bot_client.add_tick_steps(1_u32)
    bot_client.frame

    expect(hands).to eq([main])
    expect(input.use_release_pending?).to be_true
  end

  it "clears both active and queued updates at a session reset" do
    hold("shield", off)
    cooldown(duration: 30)
    bot_client.frame
    cooldown("minecraft:shield", duration: 30)
    bot_client.reset_mining_session
    tap
    expect(hands).to eq([main])
    expect(input.use_release_pending?).to be_true

    bot_client.acknowledge_use(use_packets.last.sequence)
    bot_client.sync_using_item(nil)
    tap(off)
    expect(hands).to eq([main, off])
    expect(input.use_release_pending?).to be_true
  end

  sample [false, true] do |replace|
    it "stops the reader if the raw event closes or replaces its connection" do
      origin = attach_cooldown_frame
      events = [] of Symbol
      bot_client.on(Rosegold::Event::RawPacket) do
        events << :raw
        if replace
          bot_client.attach_transport(Minecraft::IO::Memory.new)
        else
          origin.disconnect("Test ended the reader session")
        end
      end
      bot_client.on(Rosegold::Clientbound::SetCooldown) { events << :typed }

      expect { bot_client.read_next_packet }.to raise_error(Rosegold::Client::NotConnected)
      expect(events).to eq([:raw])
      tap
      expect(hands).to eq([main])
    end
  end

  it "dispatches after a raw event resets cooldown state on the same connection" do
    attach_cooldown_frame
    events = [] of Symbol
    bot_client.on(Rosegold::Event::RawPacket) do
      events << :raw
      bot_client.reset_mining_session
    end
    bot_client.on(Rosegold::Clientbound::SetCooldown) { events << :typed }

    bot_client.read_next_packet
    expect(events).to eq([:raw, :typed])
    tap
    expect(hands).to eq([main, off])
  end

  it "leaves active held use running when a matching cooldown arrives" do
    input.start_using_hand(main)
    bot_client.frame
    bot_client.sync_using_item(main)
    cooldown(duration: 30)
    5.times { bot_client.frame }

    expect(hands).to eq([main])
    expect(bot_client.player.using_item?).to be_true
    expect(bot_client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty
  end

  it "defers updates received during a yielding send until the next input frame" do
    hold("stick")
    hold("apple", off)
    arrived = Channel(Nil).new
    bot_client.on_send = ->(packet : Rosegold::Serverbound::Packet) do
      if packet.is_a?(Rosegold::Serverbound::UseItem) && packet.hand.main_hand?
        bot_client.on_send = nil
        spawn do
          cooldown
          arrived.send(nil)
        end
        arrived.receive
      end
    end

    tap
    expect(hands).to eq([main, off])
    expect(input.use_release_pending?).to be_true

    bot_client.acknowledge_use(use_packets.last.sequence)
    bot_client.sync_using_item(nil)
    tap(off)
    expect(input.use_release_pending?).to be_false
    tap(off)
    expect(input.use_release_pending?).to be_true
    expect(hands).to eq([main, off, off, off])
  end
end
