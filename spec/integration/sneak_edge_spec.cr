require "../spec_helper"

Spectator.describe "Rosegold::Bot sneak edge prevention" do
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

  it "should not fall off edge when sneaking" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Build a 1-block pillar with air on all sides at ground level
        bot.chat "/fill -2 -60 -2 4 -56 4 minecraft:air"
        bot.chat "/setblock 0 -57 0 minecraft:stone"
        bot.wait_ticks 3
        bot.chat "/tp 0 -56 0"
        bot.wait_tick
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
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Same setup: 1-block pillar with air around it
        bot.chat "/fill -2 -60 -2 4 -56 4 minecraft:air"
        bot.chat "/setblock 0 -57 0 minecraft:stone"
        bot.wait_ticks 3
        bot.chat "/tp 0 -56 0"
        bot.wait_tick
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
