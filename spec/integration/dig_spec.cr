require "../spec_helper"

Spectator.describe Rosegold::Bot do
  it "should be able to dig" do
    Rosegold::Client.new("localhost", 25565).join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 8 -60 8 8 -57 8 minecraft:dirt"
        sleep 2 # load chunks
        bot.chat "/tp 8 -56 8"
        sleep 1 # teleport

        bot.look &.down
        bot.start_digging

        until bot.feet.block == Rosegold::Vec3i.new(8, -60, 8)
          bot.wait_tick
        end

        bot.stop_digging
        expect(bot.feet.y).to be_lt -59
      end
    end
  end

  it "should stop digging when bot.stop_digging is called" do
    Rosegold::Client.new("localhost", 25565).join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 8 -60 8 8 -57 8 minecraft:dirt"
        sleep 2 # load chunks
        bot.chat "/tp 8 -56 8"
        sleep 1 # teleport

        bot.look &.down
        bot.start_digging
        bot.stop_digging

        sleep 1 # long enough to dig 1 block, if it didn't stop

        expect(bot.feet.y).to be >= -56
      end
    end
  end
end
