require "./spec_helper"

class EatSpyBot < Rosegold::Bot
  getter eat_calls = 0
  property error : Exception?

  def eat! : Nil
    @eat_calls += 1
    raise error.not_nil! if error
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

  it "stops using the hand before eat! propagates an interaction failure" do
    bot = cleanup_eating_test_bot

    expect { bot.eat! }.to raise_error(Exception, "wait failed")
    expect(bot.starts).to eq(1)
    expect(bot.stops).to eq(1)
  end
end
