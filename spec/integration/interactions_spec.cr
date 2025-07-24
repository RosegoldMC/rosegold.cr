require "../spec_helper"

Spectator.describe "Rosegold::Bot interactions" do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.wait_ticks 3
      end
    end
  end

  it "should be able to chat" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "Hello, world!"
        bot.wait_ticks 5 # Wait for chat message to be processed
      end
    end
  end

  it "should be able to dig" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 9 -60 10 9 -57 10 minecraft:dirt"
        bot.wait_ticks 5 # Wait for fill to complete
        bot.chat "/tp 9 -56 10"
        bot.wait_ticks 5 # Wait for teleport and chunk updates

        bot.look &.down
        bot.wait_ticks 5

        # Check initial block state
        initial_block = client.dimension.block_state(9, -57, 10)

        bot.start_digging
        bot.wait_ticks 20 # Give it time to break blocks
        bot.stop_digging

        # Check that block was broken
        final_block = client.dimension.block_state(9, -57, 10)
        expect(final_block).to_not eq(initial_block)
        expect(bot.feet.y).to be_lt -56.5 # Bot should have moved down a bit
      end
    end
  end

  it "should stop digging when bot.stop_digging is called" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 10 -60 9 10 -57 9 minecraft:dirt"
        bot.chat "/tp 10 -56 9"
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
        bot.chat "/tp 10 -60 10"
        bot.chat "/clear"
        bot.chat "/give @p minecraft:obsidian 64"
        bot.wait_ticks 5

        bot.inventory.pick! "obsidian"

        starting_y = bot.feet.y
        before = client.dimension.block_state(10, -60, 10)

        bot.pitch = 90
        bot.start_using_hand
        3.times do
          bot.start_jump
          15.times { bot.wait_tick }
        end

        expect(client.dimension.block_state(10, -60, 10)).to_not eq(before)
        expect(bot.feet.y).to be > starting_y
      end
    end
  end
end
