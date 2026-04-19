require "../spec_helper"

Spectator.describe "Rosegold::Bot button interactions" do
  before_all do
    admin.tp 0, -60, 0
  end
  it "should be able to push a stone button on the ground" do
    admin.fill 5, -61, 5, 7, -59, 5, "air"
    admin.wait_tick
    admin.setblock 5, -61, 5, "stone_button[face=floor]"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 5.5, -60, 5.5
        bot.wait_ticks 15

        bot.pitch = 90
        bot.wait_ticks 15

        initial_button_state = client.dimension_for_test.block_state(5, -61, 5)
        10.times do
          break if initial_button_state
          bot.wait_ticks 5
          initial_button_state = client.dimension_for_test.block_state(5, -61, 5)
        end
        expect(initial_button_state).to_not be_nil

        button_name = Rosegold::MCData.default.block_state_names[initial_button_state.as(UInt16)]
        expect(button_name).to contain("stone_button")
        expect(button_name).to contain("powered=false")

        bot.use_hand
        bot.wait_ticks 10

        final_button_state = client.dimension_for_test.block_state(5, -61, 5)
        final_name = Rosegold::MCData.default.block_state_names[final_button_state.as(UInt16)]
        expect(final_name).to contain("powered=true")

        bot.wait_ticks 30

        post_button_state = client.dimension_for_test.block_state(5, -61, 5)
        post_name = Rosegold::MCData.default.block_state_names[post_button_state.as(UInt16)]
        expect(post_name).to contain("powered=false")

        admin.fill 5, -61, 5, 7, -59, 5, "air"
        bot.wait_tick
      end
    end
  end

  it "should be able to push a stone button on the wall" do
    admin.setblock 3, -60, 3, "stone"
    admin.setblock 4, -60, 3, "stone_button[face=wall,facing=east]"
    admin.wait_tick
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 5, -60, 3.5
        bot.wait_ticks 15

        initial_button_state = client.dimension_for_test.block_state(4, -60, 3)
        expect(initial_button_state).to_not be_nil

        button_name = Rosegold::MCData.default.block_state_names[initial_button_state.as(UInt16)]
        expect(button_name).to contain("stone_button")
        expect(button_name).to contain("powered=false")

        # Look at and use the button center directly
        button_center = Rosegold::Vec3d.new(4.0625, -59.5, 3.5)
        bot.use_hand button_center
        bot.wait_ticks 10

        final_button_state = client.dimension_for_test.block_state(4, -60, 3)
        final_name = Rosegold::MCData.default.block_state_names[final_button_state.as(UInt16)]
        expect(final_name).to contain("powered=true")

        bot.wait_ticks 30

        post_button_state = client.dimension_for_test.block_state(4, -60, 3)
        post_name = Rosegold::MCData.default.block_state_names[post_button_state.as(UInt16)]
        expect(post_name).to contain("powered=false")

        admin.setblock 3, -60, 3, "air"
        admin.setblock 4, -60, 3, "air"
        bot.wait_tick
      end
    end
  end
end
