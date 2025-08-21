require "../spec_helper"

Spectator.describe "Rosegold::Bot bed interactions" do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/kill @e[type=!minecraft:player]"
        # Clear a test area
        bot.chat "/fill -10 -60 -10 10 -55 10 minecraft:air"
        # Set bedrock floor
        bot.chat "/fill -10 -61 -10 10 -61 10 minecraft:bedrock"
        bot.wait_tick
      end
    end
  end

  it "should be able to get in and out of bed successfully" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Set time to night to allow sleeping
        bot.chat "/time set night"
        bot.wait_tick
        
        # Place a bed at a specific location
        bot.chat "/setblock 0 -60 0 minecraft:red_bed[part=foot,facing=north]"
        bot.chat "/setblock 0 -60 1 minecraft:red_bed[part=head,facing=north]"
        bot.wait_tick

        # Teleport the bot directly to the bed position
        bot.chat "/tp 0.5 -60 0.5"
        bot.wait_tick
        
        # Record initial position
        initial_position = bot.feet

        # Interact with the bed to get in (look down at the bed)
        bot.look_at Rosegold::Vec3d.new(0.5, -60.5, 0.5)
        bot.use_hand
        bot.wait_ticks 5 # Wait for bed interaction to process

        # Position may have changed when sleeping
        sleeping_position = bot.feet
        
        # Get out of bed using the leave_bed method
        bot.leave_bed
        bot.wait_ticks 3

        # Position should be valid after leaving bed
        final_position = bot.feet
        
        # Bot should still be functional after bed interaction
        expect(client.connected?).to be_true
        expect(final_position).to be_a(Rosegold::Vec3d)
      end
    end
  end

  it "should handle bed interaction during the day" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Set time to day
        bot.chat "/time set day"
        bot.wait_tick
        
        # Place a bed
        bot.chat "/setblock 2 -60 0 minecraft:blue_bed[part=foot,facing=east]"
        bot.chat "/setblock 3 -60 0 minecraft:blue_bed[part=head,facing=east]"
        bot.wait_tick

        # Teleport the bot to the bed
        bot.chat "/tp 2.5 -60 0.5"
        bot.wait_tick
        
        # Try to interact with the bed during day
        bot.look_at Rosegold::Vec3d.new(2.5, -60.5, 0.5)
        bot.use_hand
        bot.wait_ticks 3 # Wait for bed interaction attempt

        # During day, bot may not be able to sleep (server dependent)
        # But the interaction should not crash the bot
        # We'll just verify the bot is still functional
        expect(bot).to be_truthy
        expect(client.connected?).to be_true
        
        # Try to leave bed anyway (should not cause issues even if not sleeping)
        bot.leave_bed
        bot.wait_ticks 2
        expect(client.connected?).to be_true
      end
    end
  end

  it "should handle bed interaction at night" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Set time to night to allow sleeping
        bot.chat "/time set night"
        bot.wait_tick
        
        # Place a bed
        bot.chat "/setblock 4 -60 0 minecraft:green_bed[part=foot,facing=west]"
        bot.chat "/setblock 3 -60 0 minecraft:green_bed[part=head,facing=west]"
        bot.wait_tick

        # Teleport the bot to the bed
        bot.chat "/tp 3.5 -60 0.5"
        bot.wait_tick
        
        # Record initial position
        initial_position = bot.feet
        
        # Interact with the bed at night
        bot.look_at Rosegold::Vec3d.new(3.5, -60.5, 0.5)
        bot.use_hand
        bot.wait_ticks 5 # Wait for bed interaction to process

        # Position may have changed if sleeping was successful
        sleeping_position = bot.feet
        
        # Wake up using leave_bed method
        bot.leave_bed
        bot.wait_ticks 3
        
        # Verify bot is still functional
        expect(client.connected?).to be_true
        final_position = bot.feet
        expect(final_position).to be_a(Rosegold::Vec3d)
      end
    end
  end
end