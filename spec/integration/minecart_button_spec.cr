require "../spec_helper"

Spectator.describe "Rosegold::Bot mounted button interactions" do
  it "presses an adjacent raised floor button while mounted at yaw -90 and pitch 15" do
    admin.chat "/kill @e[type=minecraft:minecart,tag=mounted_button_spec]"
    admin.fill 0, -60, 0, 3, -58, 0, "air"
    admin.fill 0, -61, 0, 3, -61, 0, "stone"
    admin.setblock 0, -60, 0, "rail[shape=north_south]"
    admin.setblock 1, -60, 0, "stone"
    admin.setblock 1, -59, 0, "stone_button[face=floor,facing=east,powered=false]"
    admin.chat "/summon minecraft:minecart 0.5 -59.9375 0.5 {Tags:[\"mounted_button_spec\"]}"
    admin.wait_ticks 5

    client.join_game do |client|
      bot = Rosegold::Bot.new(client)
      begin
        admin.tp 0.5, -60, 0.5
        bot.wait_ticks 5
        admin.chat "/ride #{AdminBot::TEST_PLAYER} mount @e[type=minecraft:minecart,tag=mounted_button_spec,limit=1]"

        40.times do
          break if bot.riding?("minecart")
          bot.wait_tick
        end
        expect(bot.riding?("minecart")).to be_true

        bot.look = Rosegold::Look.new(-90_f32, 15_f32)
        bot.wait_ticks 5

        initial_state = client.dimension_for_test.block_state(1, -59, 0) || raise "Button block is not loaded"
        expect(Rosegold::MCData.default.block_state_names[initial_state]).to contain("powered=false")

        bot.use_hand
        final_name = wait_for_mounted_button_state(client, bot, 1, true)
        expect(final_name).to contain("powered=true")
        expect(bot.riding?("minecart")).to be_true

        released_name = wait_for_mounted_button_state(client, bot, 1, false)
        expect(released_name).to contain("powered=false")
      ensure
        admin.chat "/ride #{AdminBot::TEST_PLAYER} dismount"
        admin.chat "/kill @e[type=minecraft:minecart,tag=mounted_button_spec]"
        admin.fill 0, -60, 0, 3, -58, 0, "air"
        admin.wait_ticks 5
      end
    end
  end
end

private def wait_for_mounted_button_state(client : Rosegold::Client, bot : Rosegold::Bot, x : Int32, powered : Bool) : String
  deadline = Time.instant + 5.seconds
  loop do
    state = client.dimension_for_test.block_state(x, -59, 0)
    name = state.try { |id| Rosegold::MCData.default.block_state_names[id] } || "unloaded"
    return name if name.includes?("powered=#{powered}") || Time.instant >= deadline
    bot.wait_tick
  end
end
