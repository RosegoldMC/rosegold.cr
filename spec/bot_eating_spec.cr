require "./spec_helper"

class EatSpyBot < Rosegold::Bot
  getter eat_calls = 0
  property error : Exception?

  def eat! : Nil
    @eat_calls += 1
    if failure = error
      raise failure
    end
  end
end

class CleanupEatBot < Rosegold::Bot
  getter starts = 0
  getter stops = 0

  def start_using_hand : Nil
    @starts += 1
  end

  def stop_using_hand : Nil
    @stops += 1
  end

  def wait_ticks(ticks : Int32) : Nil
    raise "wait failed"
  end
end

class EatingTickClient < Rosegold::Client
  getter sent_packets = [] of Rosegold::Serverbound::Packet
  property? connected = true

  def send_packet!(packet : Rosegold::Serverbound::Packet)
    sent_packets << packet
  end

  def run_tick
    interactions.tick
    emit_event Rosegold::Event::Tick.new
  end
end

class StalledEatingTickClient < EatingTickClient
  getter release_waits = 0
  property during_release_wait : Proc(Nil)?

  def wait_ticks(ticks : Int32)
    run_tick
    player.food = 18_u32
  end

  def wait_tick(timeout : Time::Span = 1.second)
    @release_waits += 1
    during_release_wait.try(&.call)
    nil
  end
end

class SplitTickEatingClient < EatingTickClient
  getter eating_waits = Channel(Nil).new
  getter eating_wait_done = Channel(Nil).new
  getter release_waits = Channel(Time::Span).new
  getter release_wakeups = Channel(Rosegold::Event::Tick?).new

  def run_interaction_phase
    interactions.tick
  end

  def wait_ticks(ticks : Int32)
    eating_waits.send(nil)
    eating_wait_done.receive
  end

  def wait_tick(timeout : Time::Span = 1.second)
    release_waits.send(timeout)
    release_wakeups.receive
  end
end

class UnreleasedTickEatingClient < StalledEatingTickClient
  getter release_timeouts = [] of Time::Span

  def wait_tick(timeout : Time::Span = 1.second)
    @release_timeouts << timeout
    sleep({timeout, 150.milliseconds}.min)
    Rosegold::Event::Tick.new
  end
end

private def stalled_eating_client
  StalledEatingTickClient.new("localhost").tap do |client|
    client.player.health = 20
    client.player.food = 10
    bread_id = Rosegold::MCData.default.items.find! { |item| item.name == "bread" }.id
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, bread_id)
  end
end

private def eating_test_client
  Rosegold::Client.new("localhost", 25565,
    offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "rosegoldtest"})
end

private def cleanup_eating_test_bot
  client = eating_test_client
  client.player.health = 20
  client.player.food = 10
  bread_id = Rosegold::MCData.default.items.find! { |item| item.name == "bread" }.id
  client.inventory_menu[36] = Rosegold::Slot.new(count: 1_u32, item_id_int: bread_id)
  CleanupEatBot.new(client)
end

Spectator.describe "Rosegold::Bot#eat" do
  it "delegates to eat! and returns nil" do
    bot = EatSpyBot.new(eating_test_client)

    expect(bot.eat).to be_nil
    expect(bot.eat_calls).to eq(1)
  end

  it "is a no-op when eating is unnecessary" do
    client = eating_test_client
    client.player.health = 20
    client.player.food = 20
    bot = Rosegold::Bot.new(client)

    expect(bot.eat).to be_nil
    expect(bot.eat!).to be_nil
  end

  it "suppresses missing-food failures while eat! remains strict" do
    client = eating_test_client
    client.player.health = 20
    client.player.food = 10
    bot = Rosegold::Bot.new(client)

    expect(bot.eat).to be_nil
    expect { bot.eat! }.to raise_error(Exception, /No edible food found in inventory/)
  end

  it "suppresses unexpected eat! failures while leaving eat! errors visible" do
    bot = EatSpyBot.new(eating_test_client)
    bot.error = Exception.new("unexpected failure")

    expect(bot.eat).to be_nil
    expect(bot.eat_calls).to eq(1)
    expect { bot.eat! }.to raise_error(Exception, "unexpected failure")
  end

  it "stops using the hand when eat suppresses an interaction failure" do
    bot = cleanup_eating_test_bot

    expect(bot.eat).to be_nil
    expect(bot.starts).to eq(1)
    expect(bot.stops).to eq(1)
  end

  it "returns from eat! only after the release tick, so the next tap is not dropped" do
    client = EatingTickClient.new("localhost")
    client.player.entity_id = 42_u64
    client.player.health = 20
    client.player.food = 10
    items = Rosegold::MCData.default.items
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, items.find! { |item| item.name == "bread" }.id)
    client.inventory_menu[45] = Rosegold::Slot.new(1_u32, items.find! { |item| item.name == "stone" }.id)
    bot = Rosegold::Bot.new(client)
    finished = false

    spawn do
      bot.eat!
      bot.use_hand(hand: :off_hand)
      finished = true
    end
    sleep 5.milliseconds
    client.run_tick
    using = Rosegold::Clientbound::SetEntityData::Entry.new(8_u8, 0_u32, 1_u8)
    Rosegold::Clientbound::SetEntityData.new(42_u64, [using]).callback(client)
    client.player.food = 18
    200.times do
      break if finished
      client.run_tick
      sleep 2.milliseconds
    end
    expect(finished).to be_true
    client.run_tick

    uses = client.sent_packets.select(Rosegold::Serverbound::UseItem)
    releases = client.sent_packets.select(Rosegold::Serverbound::PlayerAction).select(&.status.finish_using_hand?)
    expect(uses.map(&.hand)).to eq([Rosegold::Hand::MainHand, Rosegold::Hand::OffHand])
    expect(releases.size).to eq(1)
    expect(client.sent_packets.index!(&.same?(releases.first))).to be < client.sent_packets.index!(&.same?(uses.last))
  end

  it "keeps waiting when a Tick arrives from a tick whose interaction phase ran before the release" do
    client = SplitTickEatingClient.new("localhost")
    client.player.health = 20
    client.player.food = 10
    items = Rosegold::MCData.default.items
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, items.find! { |item| item.name == "bread" }.id)
    client.inventory_menu[45] = Rosegold::Slot.new(1_u32, items.find! { |item| item.name == "stone" }.id)
    bot = Rosegold::Bot.new(client)
    finished = Channel(Nil).new(1)

    spawn do
      bot.eat!
      bot.use_hand(hand: :off_hand)
      finished.send(nil)
    end

    client.eating_waits.receive
    client.run_interaction_phase
    client.sync_using_item(:main_hand)
    client.player.food = 18
    client.eating_wait_done.send(nil)
    first_timeout = client.release_waits.receive
    client.release_wakeups.send(Rosegold::Event::Tick.new)

    select
    when second_timeout = client.release_waits.receive
      expect(second_timeout).to be < first_timeout
      expect(first_timeout).to be <= 1.second
    when finished.receive
      raise "eat! returned on a Tick whose interaction phase ran before the release"
    when timeout(2.seconds)
      raise "eat! did not wait again for the release tick"
    end
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty

    client.run_interaction_phase
    client.release_wakeups.send(Rosegold::Event::Tick.new)
    select
    when finished.receive
    when timeout(2.seconds)
      raise "eat! did not return after the release tick"
    end
    client.run_tick

    uses = client.sent_packets.select(Rosegold::Serverbound::UseItem)
    releases = client.sent_packets.select(Rosegold::Serverbound::PlayerAction).select(&.status.finish_using_hand?)
    expect(uses.map(&.hand)).to eq([Rosegold::Hand::MainHand, Rosegold::Hand::OffHand])
    expect(releases.size).to eq(1)
    expect(client.sent_packets.index!(&.same?(releases.first))).to be < client.sent_packets.index!(&.same?(uses.last))
  end

  it "times out within one second total when Ticks keep arriving without the release" do
    client = UnreleasedTickEatingClient.new("localhost")
    client.player.health = 20
    client.player.food = 10
    bread_id = Rosegold::MCData.default.items.find! { |item| item.name == "bread" }.id
    client.inventory_menu[36] = Rosegold::Slot.new(1_u32, bread_id)
    bot = Rosegold::Bot.new(client)

    started = Time.instant
    expect { bot.eat! }.to raise_error(Exception, "Timed out waiting for the eating release tick")
    elapsed = Time.instant - started

    timeouts = client.release_timeouts
    expect(timeouts.size).to be > 1
    expect(timeouts.first).to be <= 1.second
    expect(timeouts.each_cons_pair.all? { |earlier, later| later < earlier }).to be_true
    expect(elapsed).to be >= 1.second
    expect(elapsed).to be < 2.seconds
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty
  end

  it "raises if the tick to release active use times out" do
    client = stalled_eating_client
    bot = Rosegold::Bot.new(client)

    expect { bot.eat! }.to raise_error(Exception, "Timed out waiting for the eating release tick")
    expect(client.release_waits).to eq(1)
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction)).to be_empty

    client.run_tick
    expect(client.sent_packets.select(Rosegold::Serverbound::PlayerAction).map(&.status)).to eq([Rosegold::Serverbound::PlayerAction::Status::FinishUsingHand])
  end

  it "does not raise if the connection closes during the release wait" do
    client = stalled_eating_client
    client.during_release_wait = -> { client.connected = false; nil }
    bot = Rosegold::Bot.new(client)

    expect(bot.eat!).to be_nil
    expect(client.release_waits).to eq(1)
  end

  it "does not raise if a session reset clears active use during the release wait" do
    client = stalled_eating_client
    client.during_release_wait = -> { client.reset_mining_session; nil }
    bot = Rosegold::Bot.new(client)

    expect(bot.eat!).to be_nil
    expect(client.release_waits).to eq(1)
  end

  it "does not wait for another tick if the server already ended active use" do
    client = stalled_eating_client
    client.on Rosegold::Event::Tick do
      client.sync_using_item(:main_hand)
      client.sync_using_item(nil)
    end
    bot = Rosegold::Bot.new(client)

    expect(bot.eat!).to be_nil
    expect(client.release_waits).to eq(0)
  end

  it "stops using the hand before eat! propagates an interaction failure" do
    bot = cleanup_eating_test_bot

    expect { bot.eat! }.to raise_error(Exception, "wait failed")
    expect(bot.starts).to eq(1)
    expect(bot.stops).to eq(1)
  end
end
