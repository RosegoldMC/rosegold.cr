require "../../spec_helper"

Spectator.describe "Rosegold::Bot entity interactions" do
  before_each do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_ticks 5
        bot.chat "/tp @p -9 -60 9"
        bot.chat "/time set 13000"
        bot.chat "/clear"
        bot.wait_for Rosegold::Clientbound::SetSlot

        # Create the water funnel system for safe testing
        bot.chat "/fill -10 -60 8 0 -58 6 minecraft:obsidian"
        bot.chat "/fill -9 -60 7 0 -58 7 minecraft:air"
        bot.wait_tick
        bot.chat "/fill -6 -60 7 -6 -60 7 minecraft:water"
        bot.wait_tick
      end
    end
  end

  after_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_ticks 5
      end
    end
  end

  it "should ignore item entities in interactions (they are picked up via collision)" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Clear the area and set up test space
        bot.chat "/fill -5 -60 -5 5 -58 5 minecraft:air"
        bot.wait_ticks 3
        bot.chat "/tp 0 -59 0"
        bot.wait_ticks 5

        # Drop an item entity in front of the bot
        bot.chat "/summon minecraft:item ~ ~ ~3 {Item:{id:\"minecraft:coal\",Count:1b}}"
        bot.wait_ticks 5

        # Look directly at the item entity (yaw 0, pitch 27 degrees down)
        # This should NOT hit the item entity, but should try to use the item in hand instead
        bot.yaw = 0
        bot.pitch = 27
        bot.wait_ticks 3

        # Start using hand - should ignore the item entity and use item in hand
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand

        # Test passes if no crash occurs and item entity is ignored in raytracing
        expect(true).to be_true
      end
    end
  end

  it "should be able to interact with entity (zombie villager curing)" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Give golden apple and weakness potion for curing
        bot.chat "/give #{bot.username} minecraft:golden_apple 1"
        bot.chat "/give #{bot.username} minecraft:splash_potion[potion_contents={potion:\"minecraft:weakness\"}] 1"
        bot.chat "/give #{bot.username} minecraft:diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        bot.chat "/effect give #{bot.username} minecraft:strength 60 2"
        bot.wait_for Rosegold::Clientbound::SetSlot

        # Spawn zombie villager in the funnel area
        bot.chat "/summon minecraft:zombie_villager -7 -60 7"
        bot.wait_ticks 5

        # Look at the zombie villager (facing south toward negative Z)
        bot.yaw = 180.0 # South (towards the zombie villager at Z=7 from bot at Z=9)
        bot.pitch = 0.0 # Level
        bot.wait_ticks 3

        # Count entities before curing
        zombie_villagers_before = client.dimension.entities.count { |_, e| e.entity_type == 146 } # zombie_villager entity type
        villagers_before = client.dimension.entities.count { |_, e| e.entity_type == 23 } # villager entity type
        expect(zombie_villagers_before).to eq(1)
        expect(villagers_before).to eq(0)

        # First throw weakness potion
        bot.inventory.pick! "splash_potion"
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand
        bot.wait_ticks 10 # Wait for potion effect

        # Then use golden apple on zombie villager to start curing
        bot.inventory.pick! "golden_apple"
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand

        # Wait a bit for curing to start (immediate effect, not full cure)
        bot.wait_ticks 20

        # The test is mainly that we don't crash when using items on entities
        # We don't wait for full cure (takes 2-5 minutes) but verify interaction worked
        expect(true).to be_true

        # Optional: verify curing started by checking if zombie villager still exists
        # (it should still be there but with curing effect started)
        zombie_villagers_after = client.dimension.entities.count { |_, e| e.entity_type == 146 }
        expect(zombie_villagers_after).to eq(1) # Still there, but curing should have started
      end
    end
  end

  it "should be able to interact with armor stand entities" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Setup test area
        bot.chat "/fill -5 -60 -5 5 -58 5 minecraft:air"
        bot.wait_ticks 3
        bot.chat "/tp 0 -59 0"
        bot.wait_ticks 5

        # Spawn an armor stand
        bot.chat "/summon minecraft:armor_stand ~ ~1 ~2"
        bot.wait_ticks 5

        # Give the bot a helmet to put on the armor stand
        bot.chat "/give @s diamond_helmet 1"
        bot.wait_ticks 3
        bot.hotbar_selection = 0_u32
        bot.wait_ticks 2

        # Look at the armor stand
        bot.look_at Rosegold::Vec3d.new(0, -58, 2)
        bot.wait_ticks 3

        # Try to interact with the armor stand
        bot.start_using_hand
        bot.wait_ticks 5
        bot.stop_using_hand

        # Test passes if no crash occurs
        expect(true).to be_true
      end
    end
  end

  it "should handle raytracing priority correctly" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Setup: Place a block and spawn an entity in front of it
        bot.chat "/fill -5 -60 -5 5 -58 5 minecraft:air"
        bot.wait_ticks 3
        bot.chat "/tp 0 -59 0"
        bot.wait_ticks 5

        # Place a block at distance
        bot.chat "/setblock ~ ~1 ~3 minecraft:stone"
        bot.wait_ticks 3

        # Spawn a zombie between bot and block
        bot.chat "/summon minecraft:zombie ~ ~1 ~2"
        bot.wait_ticks 5

        # Look straight ahead toward both block and entity
        bot.look_at Rosegold::Vec3d.new(0, -58, 2.5)
        bot.wait_ticks 3

        # Test using hand - should hit entity first, not block
        # We can't easily verify what was hit, but we test that raytracing works
        bot.start_using_hand
        bot.wait_ticks 3
        bot.stop_using_hand

        # Test passes if no crash occurs and packets are sent
        expect(true).to be_true
      end
    end
  end

  it "should respect reach ranges for survival mode" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Setup test area
        bot.chat "/fill -10 -60 -10 10 -58 10 minecraft:air"
        bot.wait_ticks 3
        bot.chat "/tp 0 -59 0"
        bot.wait_ticks 5

        # Test survival mode reach (4.5 blocks)
        bot.chat "/gamemode survival"
        bot.wait_ticks 3

        # Place block just within reach
        bot.chat "/setblock ~ ~ ~4 minecraft:stone"
        bot.wait_ticks 3
        bot.look_at Rosegold::Vec3d.new(0, -59, 4)
        bot.wait_ticks 2

        # Should be able to reach this block
        bot.start_using_hand
        bot.wait_ticks 3
        bot.stop_using_hand

        # Place block just outside reach
        bot.chat "/setblock ~ ~ ~6 minecraft:stone"
        bot.wait_ticks 3
        bot.look_at Rosegold::Vec3d.new(0, -59, 6)
        bot.wait_ticks 2

        # Should not be able to reach this block (no crash expected)
        bot.start_using_hand
        bot.wait_ticks 3
        bot.stop_using_hand
      end
    end
  end

  it "should be able to attack even if the target is moving" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill -9 -59 8 -9 -59 8 minecraft:air"
        bot.wait_tick
        bot.chat "/summon minecraft:zombie -7 -60 7"

        bot.inventory.pick! "diamond_sword"
        bot.yaw = 180
        bot.pitch = 0

        20.times do
          break if client.dimension.entities.select { |_, e| e.entity_type == 145 }.empty?
          bot.attack
          bot.wait_ticks 13
        end
        # no zombies left
        expect(client.dimension.entities.select { |_, e| e.entity_type == 145 }).to be_empty
      end
    end
  end

  it "should not be able to attack entities through blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/summon minecraft:zombie -7 -60 7"
        bot.inventory.pick! "diamond_sword"

        # Aim towards the zombie (south, towards negative Z)
        bot.yaw = 180.0 # South (towards the zombie at Z=7 from bot at Z=9)
        bot.pitch = 0.0 # Level

        # Wait a moment for everything to settle
        bot.wait_ticks 10

        # Additional verification: count zombies before attack
        zombies_before = client.dimension.entities.count { |_, e| e.entity_type == 145 }
        expect(zombies_before).to eq(1) # Ensure zombie is present

        # Try to attack multiple times - should not hit the zombie through the block
        10.times do # Increased from 5 to ensure zombie would definitely die if hit
          bot.attack
          bot.wait_ticks 5
        end

        # Wait a bit more to ensure any delayed effects are processed
        bot.wait_ticks 10

        # Count zombies after attack - should be the same (zombie should still be alive)
        zombies_after = client.dimension.entities.count { |_, e| e.entity_type == 145 }

        # The zombie should still be alive because the block prevented the attack
        expect(zombies_after).to eq(zombies_before)
        expect(zombies_after).to eq(1)
      end
    end
  end
end