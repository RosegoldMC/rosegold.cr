require "../spec_helper"

class HandUseSpecClient < Rosegold::Client
  property sent_packets = [] of Rosegold::Serverbound::Packet
  property on_send : Proc(Rosegold::Serverbound::Packet, Nil)? = nil

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
    on_send.try &.call(packet)
  end

  def interactions_for_test
    interactions
  end
end

Spectator.describe Rosegold::Interactions do
  alias Action = Rosegold::Serverbound::PlayerAction
  alias Hand = Rosegold::Hand

  def interactions
    HandUseSpecClient.new("localhost").tap do |client|
      client.inventory_menu[36] = slot("stone")
      client.inventory_menu[45] = slot("stone")
    end
  end

  def slot(name : String)
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == name }
    Rosegold::Slot.new(1_u32, item.id)
  end

  def use_packets(client)
    client.sent_packets.select(Rosegold::Serverbound::UseItem)
  end

  def release_packets(client)
    client.sent_packets.select(Action).select(&.status.finish_using_hand?)
  end

  def acknowledge(client, sequence)
    Rosegold::Clientbound::AcknowledgeBlockChange.new(sequence).callback(client)
  end

  def report_use(client, flags : UInt8)
    entry = Rosegold::Clientbound::SetEntityData::Entry.new(8_u8, 0_u32, flags)
    Rosegold::Clientbound::SetEntityData.new(client.player.entity_id, [entry]).callback(client)
  end

  def attack_swings(client)
    client.sent_packets.count { |packet| packet.is_a?(Rosegold::Serverbound::Punch) || packet.is_a?(Rosegold::Serverbound::SwingArm) }
  end

  it "cancels a held use before its first tick" do
    client = interactions
    inputs = client.interactions_for_test

    inputs.start_using_hand
    inputs.stop_using_hand
    inputs.tick

    expect(use_packets(client)).to be_empty
    expect(release_packets(client)).to be_empty
  end

  it "coalesces presses within a tick and accepts a new tap without a repeat delay" do
    client = interactions
    inputs = client.interactions_for_test

    inputs.tap_using_hand
    inputs.tap_using_hand :off_hand
    inputs.tick
    inputs.tap_using_hand
    inputs.tick
    4.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand, Hand::MainHand])
    expect(release_packets(client)).to be_empty
  end

  it "repeats an unsuccessful held use every four ticks" do
    client = interactions
    inputs = client.interactions_for_test

    inputs.start_using_hand
    inputs.tick
    3.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    inputs.tick
    expect(use_packets(client).size).to eq(2)

    inputs.stop_using_hand
    4.times { inputs.tick }
    expect(release_packets(client)).to be_empty
  end

  it "tries a fresh hold immediately even while the first hold's repeat delay runs" do
    client = interactions
    inputs = client.interactions_for_test
    inputs.start_using_hand
    inputs.tick
    inputs.stop_using_hand
    inputs.start_using_hand
    inputs.tick

    expect(use_packets(client).size).to eq(2)
    expect(release_packets(client)).to be_empty
  end

  it "does not repeat or queue another press while locally consuming offhand food" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[45] = slot("apple")

    inputs.start_using_hand :off_hand
    inputs.tick
    inputs.start_using_hand :off_hand
    5.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand])
    expect(release_packets(client)).to be_empty

    acknowledge(client, use_packets(client).first.sequence)
    client.sync_using_item(nil)
    inputs.tick
    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand, Hand::OffHand])
  end

  it "retries a held apple shortly after the server acknowledges it without starting use" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")

    inputs.start_using_hand
    inputs.tick
    acknowledge(client, use_packets(client).first.sequence)
    4.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    swings_before = attack_swings(client)

    inputs.start_digging
    inputs.tick
    expect(attack_swings(client)).to eq(swings_before + 1)
    expect(use_packets(client).size).to eq(2)
    expect(release_packets(client)).to be_empty
  end

  it "bounds an unacknowledged local prediction" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")

    inputs.start_using_hand
    inputs.tick
    19.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    inputs.tick
    expect(use_packets(client).size).to eq(2)
    expect(release_packets(client)).to be_empty
  end

  it "keeps a server-confirmed use that arrives after its acknowledgement" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.entity_id = 42_u64
    client.inventory_menu[36] = slot("apple")

    inputs.start_using_hand
    inputs.tick
    acknowledge(client, use_packets(client).first.sequence)
    2.times { inputs.tick }
    report_use(client, 1_u8)
    60.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    expect(release_packets(client)).to be_empty

    report_use(client, 0_u8)
    inputs.tick
    expect(use_packets(client).size).to eq(2)
  end

  it "does not let an older acknowledgement or stale idle flags end a newer prediction" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.entity_id = 42_u64
    client.inventory_menu[36] = slot("apple")

    inputs.start_using_hand
    inputs.tick
    sequence = use_packets(client).first.sequence
    acknowledge(client, sequence - 1)
    report_use(client, 0_u8)
    10.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)

    acknowledge(client, sequence)
    4.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    inputs.tick
    expect(use_packets(client).size).to eq(2)
  end

  it "releases an offhand food tap on the next tick with sequence zero" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[45] = slot("apple")

    inputs.tap_using_hand :off_hand
    inputs.tick
    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand])
    expect(release_packets(client)).to be_empty

    inputs.tick
    expect(release_packets(client).map(&.sequence)).to eq([0])
    expect(client.sent_packets.last).to be_a(Action)
  end

  it "releases a held consumable on the next tick and drains a simultaneous press" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")

    inputs.start_using_hand
    inputs.tick
    inputs.tap_using_hand :off_hand
    expect(release_packets(client)).to be_empty
    inputs.tick
    5.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
    expect(release_packets(client).map(&.sequence)).to eq([0])
  end

  it "queues one offhand tap through the Bot DSL" do
    client = interactions
    bot = Rosegold::Bot.new(client)

    bot.use_hand(hand: :off_hand)
    10.times { client.interactions_for_test.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand])
  end

  it "replaces a non-sustained held use with one tap in the requested hand" do
    client = interactions
    inputs = client.interactions_for_test
    inputs.start_using_hand
    inputs.tick
    Rosegold::Bot.new(client).use_hand(hand: :off_hand)
    12.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand, Hand::OffHand])
    expect(release_packets(client)).to be_empty
  end

  it "releases a food tap on the following tick without a prediction or sequence increment" do
    client = interactions
    client.inventory_menu[36] = slot("apple")
    inputs = client.interactions_for_test
    Rosegold::Bot.new(client).use_hand
    inputs.tick
    put_on_wire = use_packets(client).first.sequence
    expect(inputs.last_hand_tap_sequence).to eq(put_on_wire)
    expect(release_packets(client)).to be_empty

    inputs.tick
    release = release_packets(client).first
    expect({release.sequence, release.location, release.face}).to eq({0, Rosegold::Vec3i::ORIGIN, BlockFace::Bottom})
    expect(inputs.last_hand_tap_sequence).to eq(put_on_wire)
    expect(client.pending_block_operations.keys).to eq([put_on_wire])
    expect(client.next_sequence).to eq(put_on_wire + 1)
    40.times { inputs.tick }
    expect(use_packets(client).size).to eq(1)
    expect(release_packets(client).size).to eq(1)
  end

  it "does not predict active consumption for full hunger, a removed component or zero-duration use" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.food = 20
    client.inventory_menu[36] = slot("apple")
    inputs.tap_using_hand
    2.times { inputs.tick }

    client.player.food = 10
    apple = slot("apple")
    apple.components_to_remove.add("consumable")
    client.inventory_menu[36] = apple
    inputs.tap_using_hand
    2.times { inputs.tick }

    instant = slot("apple")
    instant.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new(0_f32)
    client.inventory_menu[36] = instant
    inputs.tap_using_hand
    2.times { inputs.tick }

    expect(use_packets(client).size).to eq(3)
    expect(release_packets(client)).to be_empty
  end

  it "uses explicit consumable and always-eat components for a custom food" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.food = 20
    custom = slot("apple")
    custom.components_to_add["food"] = Rosegold::DataComponents::Food.new(can_always_eat: true)
    custom.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new(0.2_f32)
    client.inventory_menu[36] = custom
    inputs.tap_using_hand
    2.times { inputs.tick }

    expect(use_packets(client).size).to eq(1)
    expect(release_packets(client).map(&.sequence)).to eq([0])
  end

  it "waits for synchronized use to end for an item without a local prediction" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.entity_id = 42_u64
    entries = [Rosegold::Clientbound::SetEntityData::Entry.new(8_u8, 0_u32, 3_u8)]
    active = Rosegold::Clientbound::SetEntityData.new(42_u64, entries)
    inactive = Rosegold::Clientbound::SetEntityData.new(42_u64, [Rosegold::Clientbound::SetEntityData::Entry.new(8_u8, 0_u32, 0_u8)])

    inputs.start_using_hand :off_hand
    inputs.tick
    active.callback(client)
    5.times { inputs.tick }
    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand])
    expect(release_packets(client)).to be_empty

    inactive.callback(client)
    inputs.tick
    expect(use_packets(client).map(&.hand)).to eq([Hand::OffHand, Hand::OffHand])
  end

  it "keeps the lower-level default on the main hand and treats an explicit nil as automatic" do
    client = interactions
    inputs = client.interactions_for_test

    inputs.tap_using_hand
    inputs.tick
    inputs.tap_using_hand nil
    inputs.tick

    expect(use_packets(client).map { |use| {use.hand, use.sequence} }).to eq([{Hand::MainHand, 1}, {Hand::MainHand, 2}, {Hand::OffHand, 3}])
    expect(inputs.last_hand_tap_sequence).to eq(3)
  end

  it "keeps an automatic hold on an active offhand use and releases it once with sequence zero" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.entity_id = 42_u64
    client.inventory_menu[45] = slot("shield")

    inputs.start_using_hand nil
    inputs.tick
    report_use(client, 3_u8)
    10.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand, Hand::OffHand])
    expect(release_packets(client)).to be_empty
    expect(inputs.last_hand_tap_sequence).to eq(0)

    inputs.stop_using_hand
    inputs.tick
    report_use(client, 0_u8)
    5.times { inputs.tick }
    expect(release_packets(client).map(&.sequence)).to eq([0])
    expect(use_packets(client).size).to eq(2)
  end

  it "releases an offhand use that an explicit main-hand hold does not own" do
    client = interactions
    inputs = client.interactions_for_test
    client.player.entity_id = 42_u64

    inputs.start_using_hand
    inputs.tick
    report_use(client, 3_u8)
    inputs.tick

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
    expect(release_packets(client).size).to eq(1)
  end

  it "restarts an automatic hold from the main hand on each repeat" do
    client = interactions
    inputs = client.interactions_for_test

    inputs.start_using_hand nil
    5.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand, Hand::OffHand, Hand::MainHand, Hand::OffHand])
  end

  it "does not advance when the main-hand use becomes active during its send" do
    client = interactions
    inputs = client.interactions_for_test
    client.on_send = ->(packet : Rosegold::Serverbound::Packet) do
      client.sync_using_item(Hand::MainHand) if packet.is_a?(Rosegold::Serverbound::UseItem)
      nil
    end

    inputs.tap_using_hand nil
    inputs.tick

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
  end

  it "drops the rest of a press that a send callback stops, resets, or replaces" do
    {:stop, :reset, :replace}.each do |action|
      client = interactions
      inputs = client.interactions_for_test
      client.on_send = ->(packet : Rosegold::Serverbound::Packet) do
        if packet.is_a?(Rosegold::Serverbound::UseItem) && packet.hand.main_hand?
          case action
          when :stop  then inputs.stop_using_hand
          when :reset then inputs.reset_use
          else             inputs.tap_using_hand :off_hand
          end
        end
        nil
      end

      inputs.tap_using_hand nil
      inputs.tick
      expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
      expect(client.next_sequence).to eq(2)
      expect(inputs.last_hand_tap_sequence).to eq(action == :reset ? 0 : 1)

      inputs.tick
      expected = action == :replace ? [Hand::MainHand, Hand::OffHand] : [Hand::MainHand]
      expect(use_packets(client).map(&.hand)).to eq(expected)
    end
  end

  it "drops a drained press and the held repeat when an attack swing handler stops or replaces use" do
    {:stop, :replace}.each do |action|
      client = interactions
      inputs = client.interactions_for_test
      client.on(Rosegold::Event::ArmSwing) do
        action == :stop ? inputs.stop_using_hand : inputs.start_using_hand(:off_hand)
      end

      inputs.start_using_hand nil
      inputs.start_digging
      inputs.tick

      expect(attack_swings(client)).to eq(1)
      expect(use_packets(client)).to be_empty
      expect(client.next_sequence).to eq(1)

      inputs.stop_digging
      inputs.tick
      expect(use_packets(client).map(&.hand)).to eq(action == :stop ? [] of Hand : [Hand::OffHand])
    end
  end

  it "drops a drained use press when an attack swing activates the offhand" do
    {false, true}.each do |held|
      client = interactions
      client.inventory_menu[36] = slot("shield")
      client.inventory_menu[45] = slot("shield")
      inputs = client.interactions_for_test
      client.on(Rosegold::Event::ArmSwing) { client.sync_using_item(Hand::OffHand) }

      held ? inputs.start_using_hand(nil) : inputs.tap_using_hand(nil)
      inputs.start_digging
      inputs.tick
      expect(attack_swings(client)).to eq(1)
      expect(use_packets(client)).to be_empty
      expect(client.next_sequence).to eq(1)

      if held
        5.times { inputs.tick }
        expect(use_packets(client)).to be_empty
        expect(release_packets(client)).to be_empty
        inputs.stop_using_hand
      end
      inputs.tick
      expect(release_packets(client).map(&.sequence)).to eq([0])
      expect(use_packets(client)).to be_empty
    end
  end

  it "starts sustained use for a patched stick on a tap or hold" do
    {false, true}.each do |held|
      client = interactions
      client.player.food = 10_u32
      custom = slot("stick")
      custom.components_to_add["food"] = Rosegold::DataComponents::Food.new
      custom.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new(0.05_f32)
      client.inventory_menu[36] = custom
      client.inventory_menu[45] = slot("shield")
      inputs = client.interactions_for_test

      held ? inputs.start_using_hand(nil) : inputs.tap_using_hand(nil)
      inputs.tick
      expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
      expect(release_packets(client)).to be_empty

      if held
        5.times { inputs.tick }
        expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
        expect(release_packets(client)).to be_empty
        inputs.stop_using_hand
      end
      inputs.tick
      expect(release_packets(client).map(&.sequence)).to eq([0])
      expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
    end
  end

  it "consumes instantly without starting shield use when the duration rounds down to zero ticks" do
    {0_f32, 0.049_f32}.each do |seconds|
      client = interactions
      custom = slot("shield")
      custom.components_to_add["consumable"] = Rosegold::DataComponents::Consumable.new(seconds)
      client.inventory_menu[36] = custom
      inputs = client.interactions_for_test

      inputs.tap_using_hand nil
      2.times { inputs.tick }

      expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
      expect(release_packets(client)).to be_empty
    end
  end

  it "releases legacy food outside the recognized item rules" do
    client = interactions
    client.player.food = 20_u32
    client.inventory_menu[36] = slot("golden_apple")
    inputs = client.interactions_for_test

    inputs.tap_using_hand nil
    2.times { inputs.tick }

    expect(use_packets(client).map(&.hand)).to eq([Hand::MainHand])
    expect(release_packets(client).map(&.sequence)).to eq([0])
  end

  it "stops predicting active use when the used item changes" do
    client = interactions
    inputs = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")
    inputs.tap_using_hand
    inputs.tick

    client.inventory_menu[36] = slot("stone")
    inputs.tick
    expect(release_packets(client)).to be_empty
  end
end
