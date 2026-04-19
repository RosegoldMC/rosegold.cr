require "../spec_helper"

Spectator.describe "Rosegold::Bot sneak edge prevention" do
  before_all do
    admin.setup_arena
  end

  it "should not fall off edge when sneaking" do
    admin.fill -2, -60, -2, 4, -56, 4, "air"
    admin.setblock 0, -57, 0, "stone"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 0, -56, 0
        bot.wait_ticks 2
        until client.player.on_ground?
          bot.wait_tick
        end
        expect(client.player.feet.y).to eq(-56.0)

        bot.sneak
        bot.wait_tick

        # Try to walk off the edge — should get stuck, not fall
        expect {
          bot.move_to 2, 0, stuck_timeout_ticks: 20
        }.to raise_error(Rosegold::Physics::MovementStuck)

        # Player should still be on the block, not fallen
        expect(client.player.feet.y).to be >= -56.0

        bot.unsneak
        bot.wait_tick
      end
    end
  end

  it "should fall off edge when not sneaking" do
    admin.fill -2, -60, -2, 4, -56, 4, "air"
    admin.setblock 0, -57, 0, "stone"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 0, -56, 0
        bot.wait_ticks 2
        until client.player.on_ground?
          bot.wait_tick
        end

        initial_y = client.player.feet.y

        # Without sneaking, should walk off and fall
        begin
          bot.move_to 2, 0, stuck_timeout_ticks: 40
        rescue Rosegold::Physics::MovementStuck
        end

        expect(client.player.feet.y).to be < initial_y

        bot.wait_tick
      end
    end
  end
end
