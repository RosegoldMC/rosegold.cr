require "../spec_helper"

Spectator.describe "Rosegold::Bot sneaking under top half slab" do
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

  it "should require sneaking to fit under top half slab" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Place a single top half slab above the player position to test clearance
        bot.chat "/fill 0 -60 0 0 -60 2 minecraft:air"                    # Clear area
        bot.chat "/setblock 0 -59 1 minecraft:cobblestone_slab[type=top]" # Top half slab at 1.5 blocks
        bot.chat "/tp 0 -60 0"                                            # Start position
        bot.wait_tick

        # Without sneaking, player height (1.8) would collide with slab at 1.5 blocks
        normal_height = client.player.aabb.max.y - client.player.aabb.min.y
        expect(normal_height).to be_close(1.8, 0.01)
        expect(normal_height).to be > 1.5 # Too tall for 1.5 block clearance

        # Now sneak - player should fit under the slab
        bot.sneak
        bot.wait_tick
        expect(bot.sneaking?).to be_true

        # Test that movement under the slab now works (should not raise MovementStuck)
        expect { bot.move_to 0, 1 }.not_to raise_error(Rosegold::Physics::MovementStuck)
        expect(bot.sneaking?).to be_true

        # Clean up
        bot.unsneak
        bot.chat "/setblock 0 -59 1 minecraft:air"
        bot.wait_tick
      end
    end
  end
end
