require "../spec_helper"

Spectator.describe "Rosegold::Bot movement speeds" do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_tick
      end
    end
  end

  it "should have correct movement speeds for sneak, walk, and sprint" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.sneak(true)
        start_time = Time.monotonic
        bot.move_to 5, 0
        sneak_time = Time.monotonic - start_time
        sneak_speed = 5.0 / sneak_time.total_seconds

        bot.chat "/tp 0 -60 0"
        bot.wait_tick
        bot.sneak(false)

        start_time = Time.monotonic
        bot.move_to 5, 0
        walk_time = Time.monotonic - start_time
        walk_speed = 5.0 / walk_time.total_seconds

        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.sprint(true)
        start_time = Time.monotonic
        bot.move_to 5, 0
        sprint_time = Time.monotonic - start_time
        sprint_speed = 5.0 / sprint_time.total_seconds

        expect(sneak_speed).to be_close(walk_speed * 0.3, walk_speed * 0.1)

        expect(sprint_speed).to be_close(walk_speed * 1.3, walk_speed * 0.1)

        expect(walk_speed).to be >= 3.0
        expect(walk_speed).to be <= 6.0

        bot.sprint(false)
      end
    end
  end
end
