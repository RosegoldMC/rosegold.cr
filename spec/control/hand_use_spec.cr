require "../spec_helper"

class HandUseSpecClient < Rosegold::Client
  property sent_packets = [] of Rosegold::Serverbound::Packet

  def connected?
    true
  end

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
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
