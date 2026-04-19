require "../spec_helper"

Spectator.describe "Rosegold::Bot movement" do
  before_all do
    admin.setup_arena
  end

  it "should fall due to gravity (and get held up by the ground)" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1.5, -58, 1.5
        # Wait for teleport to take effect (bot must be above ground level)
        until bot.location.y > -59 && (bot.location.x - 1.5).abs < 0.5
          bot.wait_tick
        end
        until client.player.on_ground?
          bot.wait_tick
        end
        expect(bot.location.x).to be_close(1.5, 0.1)
        expect(bot.location.y).to be_close(-60, 0.1)
        expect(bot.location.z).to be_close(1.5, 0.1)
      end
    end
  end

  it "can move to location successfully" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1, -60, 1
        bot.wait_tick

        bot.move_to 2, 2
        expect(bot.location).to eq(Rosegold::Vec3d.new(2.5, -60, 2.5))

        bot.move_to -1, -1
        expect(bot.location).to eq(Rosegold::Vec3d.new(-0.5, -60, -0.5))
      end
    end
  end

  it "should change yaw and pitch" do
    final_yaw = rand(-179..179)
    final_pitch = rand(-89..89)
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1, -60, 1

        yaw = rand(-179..179)
        pitch = rand(-89..89)
        bot.yaw = yaw
        bot.pitch = pitch
        expect(bot.yaw).to be_close(yaw, 0.1)
        expect(bot.pitch).to be_close(pitch, 0.1)

        bot.yaw = final_yaw
        bot.pitch = final_pitch
        expect(bot.yaw).to be_close(final_yaw, 0.1)
        expect(bot.pitch).to be_close(final_pitch, 0.1)

        bot.wait_ticks 3
      end
    end
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        expect(bot.yaw).to be_close(final_yaw, 0.1)
        expect(bot.pitch).to be_close(final_pitch, 0.1)
      end
    end
  end

  it "should jump and fall" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1, -60, 1
        bot.wait_tick

        initial_feet = bot.location

        bot.start_jump
        bot.wait_ticks 10

        expect(bot.location.y).to be > initial_feet.y

        until client.player.on_ground?
          bot.wait_tick
        end

        expect(bot.location.y).to be_close(initial_feet.y, 0.1)
      end
    end
  end

  describe "#move_to" do
    context "when movement is stuck" do
      it "throws Physics::MovementStuck" do
        admin.fill 1, -60, 2, 1, -60, 2, "stone"
        client.join_game do |client|
          Rosegold::Bot.new(client).try do |bot|
            admin.tp 1, -60, 1
            bot.wait_tick

            expect {
              bot.move_to 1, 2
            }.to raise_error(Rosegold::Physics::MovementStuck)

            admin.fill 1, -60, 2, 1, -60, 2, "air"
            bot.wait_tick
          end
        end
      end
    end
  end
end
