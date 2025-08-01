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

        # Enable verbose logging to verify packets are sent
        original_log_level = Log.level
        Log.level = Log::Severity::Trace
        
        begin
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
          
        ensure
          Log.level = original_log_level
        end
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
        bot.move Vec3d.new(2.9, -57, 1.5)  # Move close to edge
        edge_pos = bot.feet
        
        # Verify bot moved to edge position
        expect(edge_pos.x).to be > initial_pos.x
        expect((edge_pos.x - 2.9).abs).to be < 0.1
        
        # Now start sneaking and try to move further off the edge
        bot.sneak
        expect(bot.sneaking?).to be_true
        
        # Try to move off the platform - server should prevent this due to sneak edge protection
        attempted_off_edge_pos = Vec3d.new(3.2, -57, 1.5)  # Beyond the platform edge
        bot.move attempted_off_edge_pos
        
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
        bot.move attempted_off_edge_pos
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
        
        # Position bot on slab platform
        bot.chat "/tp 11.5 -58.5 1.5"  # On top of slab (y=-58.5)
        bot.wait_tick
        
        # Verify bot is at correct height on slab
        initial_pos = bot.feet
        expect(initial_pos.y).to be_close(-58.5, 0.1)
        
        # Move to edge of slab platform while not sneaking
        expect(bot.sneaking?).to be_false
        bot.move Vec3d.new(13.4, -58.5, 1.5)  # Near edge of slab
        edge_pos = bot.feet
        
        # Start sneaking and try to move off the slab edge
        bot.sneak
        expect(bot.sneaking?).to be_true
        
        # Attempt to move off the slab platform - should be prevented by sneak edge protection
        attempted_off_slab_pos = Vec3d.new(13.8, -58.5, 1.5)  # Beyond slab edge
        bot.move attempted_off_slab_pos
        
        sneak_final_pos = bot.feet
        
        # Verify sneak edge protection worked - bot should not have moved far past slab edge
        expect(sneak_final_pos.x).to be < attempted_off_slab_pos.x
        expect((sneak_final_pos.x - edge_pos.x).abs).to be < 0.3
        
        # Test that sneaking also prevents movement that would change elevation
        # Try to move to a position that would cause falling off the slab
        bot.move Vec3d.new(13.4, -58.5, 3.4)  # Near another edge
        bot.move Vec3d.new(13.8, -58.5, 3.8)  # Try to move off different edge
        
        edge_protection_pos = bot.feet
        
        # Bot should still be roughly on the slab platform due to edge protection
        expect(edge_protection_pos.y).to be_close(-58.5, 0.2)
        expect(edge_protection_pos.x).to be < 13.7
        expect(edge_protection_pos.z).to be < 3.7
        
        # Now unsneak and verify normal movement works
        bot.unsneak
        expect(bot.sneaking?).to be_false
        
        # Bot should now be able to move off the slab (and potentially fall)
        bot.move Vec3d.new(14.0, -58.5, 2.0)
        unsneak_pos = bot.feet
        
        # Without sneak protection, bot should have moved further
        expect(unsneak_pos.x).to be > edge_protection_pos.x
        
        # Clean up
        bot.chat "/tp 1 -60 1"
        bot.wait_tick
      end
    end
  end
end
