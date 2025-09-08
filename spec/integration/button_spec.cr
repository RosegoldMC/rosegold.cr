require "../spec_helper"

Spectator.describe "Rosegold::Bot button interactions" do
  before_all do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
      end
    end
  end
  it "should be able to push a stone button on the ground" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 5 -60 5"
        bot.wait_tick
        bot.chat "/fill 5 -61 5 7 -59 5 minecraft:air"

        bot.wait_tick
        bot.chat "/setblock 5 -61 5 minecraft:stone_button[face=floor]"
        bot.wait_tick
        bot.chat "/setblock 6 -61 5 minecraft:redstone_wire"
        bot.wait_tick
        bot.chat "/setblock 7 -61 5 minecraft:redstone_lamp"
        bot.wait_tick

        bot.pitch = 90
        bot.wait_ticks 15

        initial_lamp_state = client.dimension.block_state(7, -61, 5)

        bot.use_hand
        bot.wait_ticks 3

        final_lamp_state = client.dimension.block_state(7, -61, 5)
        expect(final_lamp_state).to_not eq(initial_lamp_state)

        bot.wait_ticks 25

        post_button_lamp_state = client.dimension.block_state(7, -61, 5)
        expect(post_button_lamp_state).to eq(initial_lamp_state)

        bot.chat "/fill 5 -61 5 7 -59 5 minecraft:air"
        bot.wait_tick
      end
    end
  end

  it "should be able to push a stone button on the wall" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/fill 5 -61 5 8 -59 5 minecraft:air"
        bot.wait_ticks 2

        bot.chat "/setblock 6 -60 5 minecraft:redstone_lamp"
        bot.chat "/setblock 7 -60 5 minecraft:stone_button[face=wall,facing=east]"
        bot.wait_ticks 3

        bot.chat "/tp 7 -61 5"
        bot.wait_ticks 2

        bot.yaw = 90
        bot.pitch = 0
        bot.wait_ticks 2

        initial_lamp_state = client.dimension.block_state(6, -60, 5)

        bot.use_hand
        bot.wait_ticks 3

        final_lamp_state = client.dimension.block_state(6, -60, 5)
        expect(final_lamp_state).to_not eq(initial_lamp_state)

        bot.wait_ticks 25

        post_button_lamp_state = client.dimension.block_state(6, -60, 5)
        expect(post_button_lamp_state).to eq(initial_lamp_state)

        bot.chat "/fill 4 -61 5 8 -59 5 minecraft:air"
        bot.wait_tick
      end
    end
  end
end
