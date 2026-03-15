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
        bot.chat "/tp 5.5 -60 5.5"
        bot.wait_ticks 5
        bot.chat "/fill 5 -61 5 7 -59 5 minecraft:air"
        bot.wait_ticks 5
        bot.chat "/setblock 5 -61 5 minecraft:stone_button[face=floor]"
        bot.wait_ticks 20

        bot.pitch = 90
        bot.wait_ticks 15

        initial_button_state = client.dimension.block_state(5, -61, 5)
        10.times do
          break if initial_button_state
          bot.wait_ticks 5
          initial_button_state = client.dimension.block_state(5, -61, 5)
        end
        expect(initial_button_state).to_not be_nil

        button_name = Rosegold::MCData.default.block_state_names[initial_button_state.as(UInt16)]
        expect(button_name).to contain("stone_button")
        expect(button_name).to contain("powered=false")

        bot.use_hand
        bot.wait_ticks 10

        final_button_state = client.dimension.block_state(5, -61, 5)
        final_name = Rosegold::MCData.default.block_state_names[final_button_state.as(UInt16)]
        expect(final_name).to contain("powered=true")

        bot.wait_ticks 30

        post_button_state = client.dimension.block_state(5, -61, 5)
        post_name = Rosegold::MCData.default.block_state_names[post_button_state.as(UInt16)]
        expect(post_name).to contain("powered=false")

        bot.chat "/fill 5 -61 5 7 -59 5 minecraft:air"
        bot.wait_tick
      end
    end
  end

  it "should be able to push a stone button on the wall" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Use z=3 to avoid any interference from other tests
        # Place stone wall and button (facing east = button on west face of block, protruding east)
        bot.chat "/setblock 3 -60 3 minecraft:stone"
        bot.chat "/setblock 4 -60 3 minecraft:stone_button[face=wall,facing=east]"
        bot.wait_ticks 20

        # Bot stands on untouched grass at (5,-60,3.5), feet at -59, eyes at -57.38
        bot.chat "/tp 5 -60 3.5"
        bot.wait_ticks 15

        initial_button_state = client.dimension.block_state(4, -60, 3)
        expect(initial_button_state).to_not be_nil

        button_name = Rosegold::MCData.default.block_state_names[initial_button_state.as(UInt16)]
        expect(button_name).to contain("stone_button")
        expect(button_name).to contain("powered=false")

        # Look at and use the button center directly
        button_center = Rosegold::Vec3d.new(4.0625, -59.5, 3.5)
        bot.use_hand button_center
        bot.wait_ticks 10

        final_button_state = client.dimension.block_state(4, -60, 3)
        final_name = Rosegold::MCData.default.block_state_names[final_button_state.as(UInt16)]
        expect(final_name).to contain("powered=true")

        bot.wait_ticks 30

        post_button_state = client.dimension.block_state(4, -60, 3)
        post_name = Rosegold::MCData.default.block_state_names[post_button_state.as(UInt16)]
        expect(post_name).to contain("powered=false")

        bot.chat "/setblock 3 -60 3 minecraft:air"
        bot.chat "/setblock 4 -60 3 minecraft:air"
        bot.wait_tick
      end
    end
  end
end
