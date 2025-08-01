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

  it "should be able to dig continuously through 3 blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Set up a column of 3 dirt blocks below the bot
        bot.chat "/fill 9 -60 10 9 -58 10 minecraft:dirt"
        bot.wait_ticks 5 # Wait for fill to complete
        bot.chat "/tp 9 -57 10"
        bot.wait_ticks 5 # Wait for teleport and chunk updates

        bot.look &.down
        bot.wait_ticks 5

        # Record initial position and block states
        initial_y = bot.feet.y
        expected_final_y = initial_y - 3.0 # Should fall through 3 blocks

        # Record initial block states
        initial_blocks = [] of (UInt16 | Nil)
        3.times do |i|
          block = client.dimension.block_state(9, (-58 - i), 10)
          initial_blocks << block
        end

        # Start continuous digging
        bot.start_digging

        # Smart wait: wait for bot to reach expected position with timeout
        timeout = 100 # 5 seconds at 20 ticks/second
        ticks_waited = 0
        until bot.feet.y <= expected_final_y || ticks_waited >= timeout
          bot.wait_tick
          ticks_waited += 1
        end

        bot.stop_digging

        # Check that bot moved down significantly (at least 2.5 blocks)
        expect(bot.feet.y).to be_lt(initial_y - 2.5)

        # Check that multiple blocks were broken
        broken_blocks = 0
        3.times do |i|
          current_block = client.dimension.block_state(9, (-58 - i), 10)
          if current_block != initial_blocks[i]
            broken_blocks += 1
          end
        end

        expect(broken_blocks).to be >= 2 # Should have broken at least 2 blocks
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
