require "../spec_helper"

Spectator.describe "Rosegold::Bot interactions" do
  before_all do
    admin.kill_entities
    admin.fill -10, -60, -10, 10, 0, 10, "air"
    admin.wait_ticks 20
  end

  it "should be able to chat" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.wait_ticks 5
        bot.chat "Hello, world!"
        bot.wait_ticks 10
      end
    end
  end

  it "should be able to dig continuously through 3 blocks" do
    admin.fill 9, -60, 10, 9, -58, 10, "dirt"
    admin.wait_ticks 5
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.clear
        admin.wait_ticks 5
        admin.tp 9, -57, 10
        bot.wait_ticks 10

        bot.look &.down
        bot.wait_ticks 5

        # Record initial position and block states
        initial_y = bot.location.y
        expected_final_y = initial_y - 3.0 # Should fall through 3 blocks

        # Record initial block states
        initial_blocks = [] of (UInt16 | Nil)
        3.times do |i|
          block = client.dimension_for_test.block_state(9, (-58 - i), 10)
          initial_blocks << block
        end

        # Start continuous digging
        bot.start_digging

        # Smart wait: wait for bot to reach expected position with timeout
        timeout = 200 # 10 seconds at 20 ticks/second
        ticks_waited = 0
        until bot.location.y <= expected_final_y || ticks_waited >= timeout
          bot.wait_tick
          ticks_waited += 1
        end

        bot.stop_digging

        # Check that bot moved down significantly (at least 2.5 blocks)
        expect(bot.location.y).to be_lt(initial_y - 2.5)

        # Check that multiple blocks were broken
        broken_blocks = 0
        3.times do |i|
          current_block = client.dimension_for_test.block_state(9, (-58 - i), 10)
          if current_block != initial_blocks[i]
            broken_blocks += 1
          end
        end

        expect(broken_blocks).to be >= 2 # Should have broken at least 2 blocks
      end
    end
  end

  it "should stop digging when bot.stop_digging is called" do
    admin.fill 10, -60, 9, 10, -57, 9, "dirt"
    admin.wait_ticks 5
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 10, -56, 9
        bot.wait_ticks 15

        bot.look &.down
        bot.wait_ticks 5
        bot.start_digging
        bot.stop_digging

        sleep 1.second # long enough to dig 1 block, if it didn't stop

        expect(bot.location.y).to be >= -56
      end
    end
  end

  it "should be able to dig stone with diamond pickaxe (in a reasonable amount of time)" do
    admin.fill 8, -60, 8, 8, -60, 8, "stone"
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.clear
        admin.wait_ticks 5
        admin.give "diamond_pickaxe"
        admin.wait_ticks 10
        admin.tp 8, -59, 8
        bot.wait_ticks 10

        # Equip the diamond pickaxe
        bot.inventory.pick! "diamond_pickaxe"
        bot.wait_ticks 5

        bot.look &.down
        bot.wait_ticks 5

        # Record initial state
        initial_block = client.dimension_for_test.block_state(8, -60, 8)

        # Verify we have stone block (state ID should be 1)
        expect(initial_block).to eq(1)

        # Start digging stone (takes ~2.3 seconds / 46 ticks with diamond pickaxe)
        bot.start_digging

        # Smart wait: stone takes about 6 ticks to break with diamond pickaxe
        timeout = 20
        ticks_waited = 0
        current_block = initial_block

        until current_block != initial_block || ticks_waited >= timeout
          bot.wait_tick
          ticks_waited += 1
          current_block = client.dimension_for_test.block_state(8, -60, 8)
        end

        bot.stop_digging

        # Check that stone block was broken
        final_block = client.dimension_for_test.block_state(8, -60, 8)
        expect(final_block).to_not eq(initial_block)

        # Verify mining completed within expected timeframe (should be ~6 ticks)
        expect(ticks_waited).to be_lt(timeout)
      end
    end
  end

  it "should be able to dig obsidian with diamond pickaxe and efficiency" do
    admin.fill 9, -60, 9, 9, -60, 9, "obsidian"
    admin.wait_ticks 5
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.clear
        admin.wait_ticks 5
        admin.give "diamond_pickaxe[enchantments={\"minecraft:efficiency\":5}]"
        admin.wait_ticks 5
        admin.tp 9, -59, 9
        bot.wait_ticks 10

        # Equip the efficiency 5 diamond pickaxe
        bot.inventory.pick! "diamond_pickaxe"
        bot.wait_ticks 5

        bot.look &.down
        bot.wait_ticks 5

        # Record initial state
        initial_block = client.dimension_for_test.block_state(9, -60, 9)

        # Verify we have obsidian block
        obsidian = Rosegold::MCData.default.blocks.find! { |blk| blk.id_str == "obsidian" }
        expect(initial_block).to eq(obsidian.min_state_id)

        # Start digging obsidian
        # With Efficiency 5, obsidian should break in moderate time
        bot.start_digging

        # obsidian takes 45 ticks to mine with diamond pickaxe and efficiency 5
        timeout = 60
        ticks_waited = 0
        current_block = initial_block

        until current_block != initial_block || ticks_waited >= timeout
          bot.wait_tick
          ticks_waited += 1
          current_block = client.dimension_for_test.block_state(9, -60, 9)
        end

        bot.stop_digging

        # Check that obsidian block was broken
        final_block = client.dimension_for_test.block_state(9, -60, 9)
        expect(final_block).to_not eq(initial_block)

        # Verify mining completed within reasonable timeframe
        expect(ticks_waited).to be_lt(timeout)
      end
    end
  end

  it "should be able to place blocks" do
    admin.kill_entities
    admin.wait_ticks 5
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 10, -60, 10
        bot.wait_ticks 10
        admin.clear
        admin.wait_ticks 10
        admin.give "obsidian", 64
        bot.wait_ticks 10

        bot.inventory.pick! "obsidian"
        bot.wait_ticks 5

        starting_y = bot.location.y
        before = client.dimension_for_test.block_state(10, -60, 10)

        bot.pitch = 90
        bot.start_using_hand
        3.times do
          bot.start_jump
          15.times { bot.wait_tick }
        end

        expect(client.dimension_for_test.block_state(10, -60, 10)).to_not eq(before)
        expect(bot.location.y).to be > starting_y
      end
    end
  end

  it "should be able to harvest a hanging vine while walking east with pitch=40" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Mimic vine farm: stone above, vine hangs below with inherited face
        admin.setblock 5, -59, 6, "stone"
        admin.setblock 5, -60, 6, "vine[west=true]"
        admin.wait_ticks 10

        vine_state = client.dimension_for_test.block_state(5, -60, 6)
        vine_name = Rosegold::MCData.default.block_state_names[vine_state.as(UInt16)]
        expect(vine_name).to contain("vine")
        expect(vine_name).to contain("west=true")

        # Bot at same Y as vine, ~1.5 blocks west
        # Eyes at y=-58.38, vine hitbox y=-60 to y=-59
        # At x-distance 1.5, ray y = -58.38 - 1.258 = -59.64 → inside vine range
        admin.tp 3.5, -60, 6.5
        admin.clear
        admin.give "shears"
        admin.wait_ticks 10

        bot.inventory.pick! "shears"
        bot.wait_ticks 5

        bot.yaw = -90
        bot.pitch = 40
        bot.wait_ticks 5

        bot.start_digging

        timeout = 40
        ticks_waited = 0
        current_state = vine_state
        until current_state != vine_state || ticks_waited >= timeout
          bot.wait_tick
          ticks_waited += 1
          current_state = client.dimension_for_test.block_state(5, -60, 6)
        end

        bot.stop_digging

        final_state = client.dimension_for_test.block_state(5, -60, 6)
        expect(final_state).to_not eq(vine_state)
        expect(ticks_waited).to be_lt(timeout)
      end
    end
  end

  it "should raytrace wheat crops with age-dependent hitboxes" do
    admin.setblock 6, -60, 6, "farmland"
    admin.setblock 6, -59, 6, "wheat[age=0]"
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 6.5, -60, 7.5
        admin.clear
        admin.give "bone_meal", 10
        bot.wait_ticks 5

        # Verify wheat was created at age 0
        wheat_age_0 = client.dimension_for_test.block_state(6, -59, 6)
        expect(wheat_age_0).to_not be_nil
        age_0_name = Rosegold::MCData.default.block_state_names[wheat_age_0.as(UInt16)]
        expect(age_0_name).to eq("wheat[age=0]")

        # Pick bonemeal and count initial amount
        bot.inventory.pick! "bone_meal"
        bot.wait_ticks 2
        initial_bonemeal = bot.main_hand.count

        # Look horizontally at tiny age-0 wheat (should miss - too short at 0.125 blocks)
        bot.yaw = 180
        bot.pitch = 0
        bot.wait_ticks 2

        # Try to use bonemeal (should miss the tiny wheat)
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand
        bot.wait_ticks 5

        # Verify bonemeal was NOT consumed (ray passed above tiny wheat)
        expect(bot.main_hand.count).to eq(initial_bonemeal)
        wheat_after_miss = client.dimension_for_test.block_state(6, -59, 6)
        expect(wheat_after_miss).to eq(wheat_age_0)

        # Now look down at an angle that should hit the wheat
        bot.pitch = 35
        bot.wait_ticks 2

        # Use bonemeal on wheat (should hit this time)
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand
        bot.wait_ticks 5

        # Verify bonemeal was consumed (successfully hit the wheat)
        expect(bot.main_hand.count).to be < initial_bonemeal

        # Verify wheat grew (bonemeal actually worked)
        wheat_after_growth = client.dimension_for_test.block_state(6, -59, 6)
        expect(wheat_after_growth).to_not eq(wheat_age_0)
      end
    end
  end
end
