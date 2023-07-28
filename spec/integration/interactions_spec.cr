require "../spec_helper"

Spectator.describe Rosegold::Bot do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 8 -60 8 8 0 8 minecraft:air"
        bot.wait_tick
      end
    end
  end

  it "should be able to dig" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 8 -60 8 8 -57 8 minecraft:dirt"
        bot.chat "/tp 8 -56 8"
        bot.wait_tick

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
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 8 -60 8 8 -57 8 minecraft:dirt"
        bot.chat "/tp 8 -56 8"
        bot.wait_tick

        bot.look &.down
        bot.start_digging
        bot.stop_digging

        sleep 1 # long enough to dig 1 block, if it didn't stop

        expect(bot.feet.y).to be >= -56
      end
    end
  end

  it "should be able to place blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/give #{bot.username} dirt 64"
        bot.wait_for Rosegold::Clientbound::SetSlot
        starting_y = bot.feet.y

        bot.pitch = 90
        bot.inventory.pick! "dirt"
        bot.start_using_hand
        2.times do
          bot.start_jump
          bot.wait_ticks 20
        end

        expect(starting_y).to be < bot.feet.y
      end
    end
  end
end
