require "../spec_helper"

Spectator.describe "Rosegold::Bot interactions" do
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
        bot.chat "/fill 0 -60 0 0 -57 0 minecraft:dirt"
        bot.wait_ticks 5 # Wait for fill to complete
        bot.chat "/tp 0 -56 0"
        bot.wait_ticks 5 # Wait for teleport and chunk updates

        bot.look &.down

        # Check initial block state
        initial_block = client.dimension.block_state(0, -57, 0)

        bot.start_digging
        bot.wait_ticks 20 # Give it time to break blocks
        bot.stop_digging

        # Check that block was broken
        final_block = client.dimension.block_state(0, -57, 0)
        expect(final_block).to_not eq(initial_block)
        expect(bot.feet.y).to be_lt -56.5 # Bot should have moved down a bit
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

        sleep 1.second # long enough to dig 1 block, if it didn't stop

        expect(bot.feet.y).to be >= -56
      end
    end
  end

  it "should be able to place blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        starting_y = bot.feet.y

        bot.pitch = 90
        bot.start_using_hand
        2.times do
          bot.start_jump
          15.times { bot.wait_tick }
        end

        expect(bot.feet.y).to be > starting_y
      end
    end
  end
end
