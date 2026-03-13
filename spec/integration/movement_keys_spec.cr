require "../spec_helper"

Spectator.describe "Rosegold::Bot movement keys" do
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

  it "moves forward when forward key is pressed" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.yaw = 0.0 # face south (+Z)
        initial_z = bot.location.z

        bot.keys.press Rosegold::MovementKeys::Key::Forward
        bot.wait_ticks 10
        bot.keys.release_all

        expect(bot.location.z).to be > initial_z
      end
    end
  end

  it "moves backward when backward key is pressed" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.yaw = 0.0 # face south (+Z)
        initial_z = bot.location.z

        bot.keys.press Rosegold::MovementKeys::Key::Backward
        bot.wait_ticks 10
        bot.keys.release_all

        expect(bot.location.z).to be < initial_z
      end
    end
  end

  it "strafes left when left key is pressed" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.yaw = 0.0 # face south (+Z), left is +X
        initial_x = bot.location.x

        bot.keys.press Rosegold::MovementKeys::Key::Left
        bot.wait_ticks 10
        bot.keys.release_all

        expect(bot.location.x).to be > initial_x
      end
    end
  end

  it "moves diagonally with two keys pressed" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.yaw = 0.0 # face south
        initial = bot.location

        bot.keys.press Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Left
        bot.wait_ticks 10
        bot.keys.release_all

        expect(bot.location.z).to be > initial.z
        expect(bot.location.x).to be > initial.x
      end
    end
  end

  it "stops moving after release_all" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.yaw = 0.0
        bot.keys.press Rosegold::MovementKeys::Key::Forward
        bot.wait_ticks 10
        bot.keys.release_all

        # Wait for velocity to decay
        bot.wait_ticks 10
        settled = bot.location

        bot.wait_ticks 5
        expect(bot.location.z).to be_close(settled.z, 0.01)
      end
    end
  end

  it "move_to clears movement keys on completion" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.chat "/tp 0 -60 0"
        bot.wait_tick

        bot.keys.press Rosegold::MovementKeys::Key::Left
        bot.move_to 2, 2

        expect(bot.keys.none?).to be_true
      end
    end
  end

  it "stop_moving clears movement keys" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.keys.press Rosegold::MovementKeys::Key::Forward | Rosegold::MovementKeys::Key::Right
        bot.stop_moving

        expect(bot.keys.none?).to be_true
      end
    end
  end
end
