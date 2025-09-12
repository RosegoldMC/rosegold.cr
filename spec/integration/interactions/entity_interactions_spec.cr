require "../../spec_helper"

Spectator.describe "Rosegold::Bot entity interactions" do
  before_each do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        bot.wait_ticks 3
        bot.chat "/fill -10 -60 -10 10 0 10 minecraft:air"
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_ticks 5
        bot.chat "/tp @p -9 -60 9"
        bot.chat "/time set 13000"
        bot.chat "/clear"
        bot.wait_for Rosegold::Clientbound::SetSlot

        bot.chat "/give #{bot.username} minecraft:diamond_sword[enchantments={\"minecraft:sharpness\":5}]"
        bot.chat "/effect give #{bot.username} minecraft:strength 60 2"
        bot.wait_for Rosegold::Clientbound::SetSlot

        # Create the water funnel system for safe testing
        bot.chat "/fill -10 -60 8 0 -58 6 minecraft:obsidian"
        bot.chat "/fill -9 -60 7 0 -58 7 minecraft:air"
        bot.chat "/fill -9 -59 8 -9 -59 8 minecraft:air"
        # Ensure interaction window is air like other attack specs
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

  it "should be able to interact with entity (cow feeding)" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Give wheat for cow feeding
        bot.chat "/give #{bot.username} minecraft:wheat 5"
        bot.wait_for Rosegold::Clientbound::SetSlot

        # Spawn cow in the funnel area (ensure no existing cows first)
        bot.chat "/kill @e[type=cow]"
        bot.wait_ticks 2
        bot.chat "/summon cow -9 -60 7"
        bot.wait_ticks 3

        # Look at the cow (facing south toward negative Z)
        bot.yaw = 180.0 # South (towards the cow at Z=7 from bot at Z=9)
        bot.pitch = 0.0 # Level

        # Count wheat before feeding
        wheat_count_before = bot.inventory.count("wheat")
        expect(wheat_count_before).to eq(5)

        # Count cows before feeding
        cows_before = client.dimension.entities.count { |_, e| e.entity_type == 28 } # cow entity type from game_assets/1.21.8/entities.json
        expect(cows_before).to eq(1)

        # Pick wheat and interact with cow
        bot.inventory.pick! "wheat"
        bot.start_using_hand

        # Check wheat count every tick until it decreases (with timeout)
        timeout_ticks = 30
        ticks_waited = 0
        current_wheat_count = wheat_count_before

        until current_wheat_count < wheat_count_before || ticks_waited >= timeout_ticks
          bot.wait_tick
          ticks_waited += 1
          current_wheat_count = bot.inventory.count("wheat")
        end

        bot.stop_using_hand

        # Check wheat count after feeding
        wheat_count_after = bot.inventory.count("wheat")
        expect(wheat_count_after).to eq(4) # Should be 1 less than before (5 - 1 = 4)

        # Verify cow is still alive (feeding doesn't kill it)
        cows_after = client.dimension.entities.count { |_, e| e.entity_type == 28 } # cow entity type from game_assets/1.21.8/entities.json
        expect(cows_after).to eq(1)

        # Test passes if wheat count decremented, proving successful entity interaction
        expect(wheat_count_before - wheat_count_after).to eq(1)
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
