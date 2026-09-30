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
  def interactions
    HandUseSpecClient.new("localhost").tap do |client|
      client.inventory_menu[36] = slot("stone")
    end
  end

  def slot(name : String)
    item = Rosegold::MCData.default.items.find! { |candidate| candidate.name == name }
    Rosegold::Slot.new(1_u32, item.id)
  end

  def use_packets(client)
    client.sent_packets.select(Rosegold::Serverbound::UseItem)
  end

  it "cancels a held use before its first tick" do
    client = interactions
    interactions = client.interactions_for_test

    interactions.start_using_hand
    interactions.stop_using_hand
    interactions.tick

    expect(use_packets(client)).to be_empty
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty
  end

  it "queues repeated taps behind the existing use delay" do
    client = interactions
    interactions = client.interactions_for_test

    interactions.tap_using_hand
    interactions.tick
    interactions.tap_using_hand
    3.times { interactions.tick }

    expect(use_packets(client).size).to eq(1)

    interactions.tick

    expect(use_packets(client).size).to eq(2)
  end

  it "lets a tap proceed immediately after stopping a held use" do
    client = interactions
    interactions = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")

    interactions.start_using_hand
    interactions.tick
    interactions.stop_using_hand
    interactions.tap_using_hand
    interactions.tick

    expect(use_packets(client).size).to eq(2)
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction).map(&.status)).to eq([
      Rosegold::Serverbound::PlayerAction::Status::FinishUsingHand,
    ])
  end

  it "uses the selected offhand item to choose the repeat delay" do
    client = interactions
    interactions = client.interactions_for_test
    client.inventory_menu[45] = slot("apple")

    interactions.start_using_hand :off_hand
    interactions.tick
    4.times { interactions.tick }

    use_packets(client).tap do |packets|
      expect(packets.size).to eq(1)
      expect(packets.first.hand).to eq(Rosegold::Hand::OffHand)
    end
  end

  it "does not restart a held use when the same hand is requested again" do
    client = interactions
    interactions = client.interactions_for_test
    client.inventory_menu[36] = slot("apple")

    interactions.start_using_hand
    interactions.tick
    interactions.start_using_hand
    interactions.tick
    interactions.stop_using_hand

    expect(use_packets(client).size).to eq(1)
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction).map(&.status)).to eq([
      Rosegold::Serverbound::PlayerAction::Status::FinishUsingHand,
    ])
  end

  it "queues one offhand tap through the Bot DSL" do
    client = interactions
    bot = Rosegold::Bot.new(client)

    bot.use_hand(hand: :off_hand)
    10.times { client.interactions_for_test.tick }

    expect(use_packets(client).size).to eq(1)
    expect(use_packets(client).first.hand).to eq(Rosegold::Hand::OffHand)
  end
end
