require "../spec_helper"

Spectator.describe "Rosegold::Bot stairs movement" do
  before_all do
    admin.kill_entities
    admin.fill -10, -60, -10, 10, -55, 10, "air"
    admin.fill -10, -61, -10, 10, -61, 10, "bedrock"
    admin.wait_tick
  end

  it "should be able to walk up actual stone stairs" do
    admin.setblock 1, -60, 2, "stone_stairs[facing=south]"
    admin.setblock 1, -60, 3, "stone"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1, -60, 1
        bot.wait_tick

        initial_y = bot.location.y
        expect(initial_y).to be_close(-60.0, 0.1)

        # Move to 1,3 - this should make the bot walk up the stone stairs
        bot.move_to 1, 3

        # Should be one block higher due to walking up the stairs
        final_y = bot.location.y
        expect(final_y).to be > initial_y
        expect(final_y).to be_close(-59.0, 0.1)

        # Should reach the target position
        expect(bot.location).to eq(Rosegold::Vec3d.new(1.5, -59, 3.5))
      end
    end
  end
end
