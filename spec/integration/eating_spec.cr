require "../spec_helper"

Spectator.describe "Rosegold::Bot eating" do
  it "eats while the crosshair targets a plain block" do
    admin.fill -5, -60, -5, 5, -55, 5, "air"
    admin.setblock 0, -61, 0, "stone"
    admin.wait_ticks 3

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.clear
        admin.tp 0.5, -60, 0.5
        bot.wait_ticks 10

        bot.look &.down
        bot.wait_ticks 5

        floor_state = client.dimension_for_test.block_state(0, -61, 0)
        expect(floor_state).to_not be_nil

        admin.effect_give "hunger", 120, 40
        hunger_timeout = 1200
        waited = 0
        until bot.food < 15 || waited >= hunger_timeout
          bot.wait_tick
          waited += 1
        end
        admin.effect_clear
        bot.wait_ticks 3
        expect(bot.food).to be_lt(18)

        food_before = bot.food

        admin.give "bread", 64
        bot.wait_ticks 5

        bot.eat!

        expect(bot.food).to be > food_before
        expect(bot.food).to be >= 18

        # Block must survive: eating right-clicks but never breaks the target.
        expect(client.dimension_for_test.block_state(0, -61, 0)).to eq(floor_state)
      end
    end
  end
end
