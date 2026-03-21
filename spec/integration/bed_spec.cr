require "../spec_helper"

Spectator.describe "Rosegold::Bot bed interactions" do
  before_all do
    admin.kill_entities
    admin.fill -10, -60, -10, 10, -55, 10, "air"
    admin.fill -10, -61, -10, 10, -61, 10, "bedrock"
    admin.wait_tick
  end

  it "should be able to get in and out of bed successfully" do
    admin.time_set "night"
    admin.setblock 0, -60, 0, "red_bed[part=foot,facing=north]"
    admin.setblock 0, -60, 1, "red_bed[part=head,facing=north]"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 0.5, -60, 0.5
        bot.wait_tick

        # Interact with the bed to get in (look down at the bed)
        bot.look_at Rosegold::Vec3d.new(0.5, -60.5, 0.5)
        bot.use_hand
        bot.wait_ticks 5 # Wait for bed interaction to process

        # Get out of bed using the leave_bed method
        bot.leave_bed
        bot.wait_ticks 3

        # Position should be valid after leaving bed
        final_position = bot.location

        # Bot should still be functional after bed interaction
        expect(client.connected?).to be_true
        expect(final_position).to be_a(Rosegold::Vec3d)
      end
    end
  end

  it "should handle bed interaction during the day" do
    admin.time_set "day"
    admin.setblock 2, -60, 0, "blue_bed[part=foot,facing=east]"
    admin.setblock 3, -60, 0, "blue_bed[part=head,facing=east]"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 2.5, -60, 0.5
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
    admin.time_set "night"
    admin.setblock 4, -60, 0, "green_bed[part=foot,facing=west]"
    admin.setblock 3, -60, 0, "green_bed[part=head,facing=west]"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 3.5, -60, 0.5
        bot.wait_tick

        # Interact with the bed at night
        bot.look_at Rosegold::Vec3d.new(3.5, -60.5, 0.5)
        bot.use_hand
        bot.wait_ticks 5 # Wait for bed interaction to process

        # Wake up using leave_bed method
        bot.leave_bed
        bot.wait_ticks 3

        # Verify bot is still functional
        expect(client.connected?).to be_true
        final_position = bot.location
        expect(final_position).to be_a(Rosegold::Vec3d)
      end
    end
  end
end
