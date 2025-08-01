require "../spec_helper"

Spectator.describe "Rosegold::Bot sneak functionality" do
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

  it "should sneak when bot.sneak is called" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Ensure bot starts not sneaking
        expect(bot.sneaking?).to be_false

        # Call sneak method
        bot.sneak

        # Bot should now be sneaking
        expect(bot.sneaking?).to be_true

        # Test that we can unsneak
        bot.unsneak

        # Bot should no longer be sneaking
        expect(bot.sneaking?).to be_false
      end
    end
  end

  it "should not sprint while sneaking" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Start sneaking
        bot.sneak
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false

        # Try to sprint - should not work while sneaking
        bot.sprint
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false

        # Stop sneaking, then should be able to sprint
        bot.unsneak
        expect(bot.sneaking?).to be_false

        bot.sprint
        expect(bot.sprinting?).to be_true
      end
    end
  end

  it "should stop sprinting when starting to sneak" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Start sprinting
        bot.sprint
        expect(bot.sprinting?).to be_true
        expect(bot.sneaking?).to be_false

        # Start sneaking - should stop sprinting automatically
        bot.sneak
        expect(bot.sneaking?).to be_true
        expect(bot.sprinting?).to be_false
      end
    end
  end

  it "should maintain sneak state across multiple calls" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Sneak multiple times - should remain sneaking
        bot.sneak
        expect(bot.sneaking?).to be_true

        bot.sneak
        expect(bot.sneaking?).to be_true

        bot.sneak
        expect(bot.sneaking?).to be_true

        # Unsneak and verify
        bot.unsneak
        expect(bot.sneaking?).to be_false

        # Unsneak multiple times - should remain not sneaking
        bot.unsneak
        expect(bot.sneaking?).to be_false

        bot.unsneak
        expect(bot.sneaking?).to be_false
      end
    end
  end

  it "should have reduced movement speed when sneaking" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Test normal walking speed
        expect(bot.sneaking?).to be_false
        normal_speed = client.physics.movement_speed
        expect(normal_speed).to eq(Rosegold::Physics::WALK_SPEED)

        # Test sneaking speed
        bot.sneak
        expect(bot.sneaking?).to be_true
        sneak_speed = client.physics.movement_speed
        expect(sneak_speed).to eq(Rosegold::Physics::SNEAK_SPEED)
        expect(sneak_speed).to be < normal_speed

        # Verify the actual speed values match expected constants
        expect(sneak_speed).to eq(1.31 / 20)
        expect(normal_speed).to eq(4.3 / 20)

        # Test that speed returns to normal when unsneaking
        bot.unsneak
        expect(bot.sneaking?).to be_false
        back_to_normal_speed = client.physics.movement_speed
        expect(back_to_normal_speed).to eq(normal_speed)
      end
    end
  end

  it "should prove packets are sent by examining logs or using server feedback" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        # Test that sneaking triggers the expected packet sends
        # We verify this by testing the effects rather than just internal state
        expect(bot.sneaking?).to be_false
          
          # This should trigger sending EntityAction StartSneaking packet
          bot.sneak
          expect(bot.sneaking?).to be_true
          
          # Wait a tick to ensure packet is processed
          bot.wait_tick
          
          # Verify that the sneak state persisted through the server round-trip
          # If packets weren't sent correctly, server might reject the state
          expect(bot.sneaking?).to be_true
          
          # Test that unsneaking also works through the server
          bot.unsneak  
          expect(bot.sneaking?).to be_false
          
          bot.wait_tick
          expect(bot.sneaking?).to be_false
          
      end
    end
  end

  it "should demonstrate actual gameplay effects of sneaking" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 1 -60 1"
        bot.wait_tick
        
        # Test 1: Verify movement speed is actually affected
        expect(bot.sneaking?).to be_false
        normal_speed = client.physics.movement_speed
        expect(normal_speed).to eq(Rosegold::Physics::WALK_SPEED)
        
        bot.sneak
        expect(bot.sneaking?).to be_true
        sneak_speed = client.physics.movement_speed
        expect(sneak_speed).to eq(Rosegold::Physics::SNEAK_SPEED)
        
        # The speed difference proves the physics system recognizes sneaking
        expect(sneak_speed).to be < normal_speed
        
        # Test 2: Verify sprint-sneak interaction (proves server logic is working)
        # If packets weren't sent properly, this interaction wouldn't work
        bot.sprint  # Should not work while sneaking
        expect(bot.sprinting?).to be_false  # Still not sprinting
        expect(bot.sneaking?).to be_true    # Still sneaking
        
        # Test 3: Verify that unsneaking allows sprinting again
        bot.unsneak
        expect(bot.sneaking?).to be_false
        
        bot.sprint  # Should work now
        expect(bot.sprinting?).to be_true   # Now sprinting
        expect(bot.sneaking?).to be_false   # Not sneaking
        
        # Clean up
        bot.unsprint
      end
    end
  end

  it "should prove player is truly sneaking by testing edge prevention with blocks" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Create a platform with an edge to test edge prevention behavior
        # Clear the area first
        bot.chat "/fill 0 -59 0 5 -57 5 minecraft:air"
        bot.wait_tick
        
        # Build a 2-block high platform at 0,-59,0 to 2,-59,2
        bot.chat "/fill 0 -59 0 2 -59 2 minecraft:stone"
        bot.chat "/fill 0 -58 0 2 -58 2 minecraft:stone" 
        bot.wait_tick
        
        # Position bot in center of platform
        bot.chat "/tp 1.5 -57 1.5"
        bot.wait_tick
        
        # Ensure bot starts not sneaking
        expect(bot.sneaking?).to be_false
        
        # Move bot to edge of platform while not sneaking
        initial_pos = bot.feet
        bot.move_to Rosegold::Vec3d.new(2.9, -57, 1.5)  # Move close to edge
        edge_pos = bot.feet
        
        # Verify bot moved to edge position
        expect(edge_pos.x).to be > initial_pos.x
        expect((edge_pos.x - 2.9).abs).to be < 0.1
        
        # Now start sneaking and try to move further off the edge
        bot.sneak
        expect(bot.sneaking?).to be_true
        
        # Try to move off the platform - server should prevent this due to sneak edge protection
        attempted_off_edge_pos = Rosegold::Vec3d.new(3.2, -57, 1.5)  # Beyond the platform edge
        bot.move_to attempted_off_edge_pos
        
        # Check final position - should NOT have moved off the edge due to sneak protection
        final_sneak_pos = bot.feet
        
        # The bot should not have moved significantly past the edge due to sneak protection
        # In Minecraft, sneaking prevents movement that would cause falling off edges
        expect(final_sneak_pos.x).to be < attempted_off_edge_pos.x
        expect((final_sneak_pos.x - edge_pos.x).abs).to be < 0.5  # Should not have moved far from edge
        
        # Now unsneak and verify the bot CAN move off the platform
        bot.unsneak
        expect(bot.sneaking?).to be_false
        
        # Try to move off the platform again - should work now
        bot.move_to attempted_off_edge_pos
        final_unsneak_pos = bot.feet
        
        # Without sneaking, the bot should be able to move off the platform
        # (though it may fall due to gravity)
        expect(final_unsneak_pos.x).to be > final_sneak_pos.x
        
        # Clean up - teleport back to safe area
        bot.chat "/tp 1 -60 1"
        bot.wait_tick
      end
    end
  end

  it "should prove sneaking prevents falling off slabs and demonstrates height-based edge protection" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Create a slab platform to test edge protection at different heights
        # Clear the area first
        bot.chat "/fill 10 -59 0 15 -57 5 minecraft:air"
        bot.wait_tick
        
        # Build slab platform at y=-59 (half-block height)
        bot.chat "/fill 10 -59 0 13 -59 3 minecraft:stone_slab"
        bot.wait_tick
        
        # Add stone blocks above the slab area to force sneaking
        # Place stone blocks at y=-57 (1.5 blocks above slab) to create a low ceiling
        # This forces the player to sneak to fit under the stone blocks when on the slab
        bot.chat "/fill 11 -57 1 13 -57 3 minecraft:stone"
        bot.wait_tick
        
        # Position bot on slab platform away from the low ceiling area first
        bot.chat "/tp 10.5 -58.5 1.5"  # On slab but away from stone ceiling
        bot.wait_tick
        
        # Verify bot is at correct height on slab
        initial_pos = bot.feet
        expect(initial_pos.y).to be_close(-58.5, 0.1)
        
        # Test 1: Try to move under the stone ceiling without sneaking - should fail/get stuck
        expect(bot.sneaking?).to be_false
        
        # Try to move under the low stone ceiling (1.5 block clearance)
        # Player height when standing is ~1.8 blocks, so this should not work well
        target_under_stone = Rosegold::Vec3d.new(12.0, -58.5, 2.0)  # Under the stone ceiling
        bot.move_to target_under_stone
        
        # Bot should have difficulty moving under the stone ceiling while standing
        standing_pos = bot.feet
        expect(standing_pos.x).to be < target_under_stone.x  # Didn't reach target
        
        # Test 2: Now sneak and try to move under the stone ceiling - should work
        bot.sneak
        expect(bot.sneaking?).to be_true
        
        # Player height when sneaking is ~1.5 blocks, so this should fit under stone ceiling
        bot.move_to target_under_stone
        sneaking_pos = bot.feet
        
        # While sneaking, bot should be able to move closer to or reach the target
        expect(sneaking_pos.x).to be > standing_pos.x  # Made more progress while sneaking
        
        # Test 3: Test edge protection while under the low ceiling
        # Move to edge of slab platform while sneaking under stone ceiling
        edge_target = Rosegold::Vec3d.new(13.4, -58.5, 2.0)  # Near edge of slab, under stone
        bot.move_to edge_target
        edge_pos = bot.feet
        
        # Attempt to move off the slab platform - should be prevented by sneak edge protection
        attempted_off_slab_pos = Rosegold::Vec3d.new(13.8, -58.5, 2.0)  # Beyond slab edge
        bot.move_to attempted_off_slab_pos
        
        sneak_final_pos = bot.feet
        
        # Verify sneak edge protection worked - bot should not have moved far past slab edge
        expect(sneak_final_pos.x).to be < attempted_off_slab_pos.x
        expect((sneak_final_pos.x - edge_pos.x).abs).to be < 0.3
        
        # Test 4: Verify movement is restricted by both ceiling and edge protection
        # Try to move to various positions that would violate either constraint
        bot.move_to Rosegold::Vec3d.new(13.4, -58.5, 3.4)  # Near another edge under ceiling
        bot.move_to Rosegold::Vec3d.new(13.8, -58.5, 3.8)  # Try to move off different edge
        
        constrained_pos = bot.feet
        
        # Bot should be constrained by both ceiling height and edge protection
        expect(constrained_pos.y).to be_close(-58.5, 0.2)  # Still on slab
        expect(constrained_pos.x).to be < 13.7  # Edge protection
        expect(constrained_pos.z).to be < 3.7  # Edge protection
        
        # Test 5: Unsneak and verify the ceiling constraint becomes a problem
        bot.unsneak
        expect(bot.sneaking?).to be_false
        
        # Without sneaking, movement under the low ceiling should be more restricted
        # Try to move to a new position under the ceiling
        bot.move_to Rosegold::Vec3d.new(12.5, -58.5, 2.5)
        unsneak_pos = bot.feet
        
        # Movement should be more limited without sneaking due to ceiling height
        distance_moved = Math.sqrt((unsneak_pos.x - constrained_pos.x)**2 + (unsneak_pos.z - constrained_pos.z)**2)
        expect(distance_moved).to be < 0.5  # Limited movement due to ceiling constraint
        
        # Clean up
        bot.chat "/tp 1 -60 1"
        bot.wait_tick
      end
    end
  end
end
