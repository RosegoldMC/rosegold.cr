require "../spec_helper"

Spectator.describe "Rosegold::Bot stairs movement" do
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

  it "should be able to walk up actual stone stairs" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/setblock 1 -60 2 minecraft:stone_stairs[facing=south]" # Actual stairs facing north
        bot.chat "/setblock 1 -60 3 minecraft:stone"                      # Destination block (one level up)

        bot.wait_tick

        # Start the bot at 1,1
        bot.chat "/tp 1 -60 1"
        bot.wait_tick

        initial_y = bot.feet.y
        expect(initial_y).to be_close(-60.0, 0.1)

        # Move to 1,3 - this should make the bot walk up the stone stairs
        bot.move_to 1, 3

        # Should be one block higher due to walking up the stairs
        final_y = bot.feet.y
        expect(final_y).to be > initial_y
        expect(final_y).to be_close(-59.0, 0.1)

        # Should reach the target position
        expect(bot.feet).to eq(Rosegold::Vec3d.new(1.5, -59, 3.5))
      end
    end
  end
end
