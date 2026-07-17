require "../spec_helper"

# A player standing flush against a full block (melon) must be able to walk parallel to that
# face — vanilla slides along the wall instead of sticking. Flush position matches vanilla:
# block face at 2.0 minus the float half-width (double)0.3f => 1.699999988079071. Regression
# for a reported wall-stick / server snap-back when sliding across a full-block face.
Spectator.describe "Rosegold::Bot melon slide" do
  FLUSH_Z = 2.0 - 0.30000001192092896

  before_all do
    admin.setup_arena
  end

  it "slides along the face via move_to and parks at the vanilla flush coordinate" do
    admin.setblock 2, -60, 2, "melon"
    admin.wait_tick

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1.9, -60, 1.5
        bot.wait_ticks 3

        expect { bot.move_to 1.9, 2.0 }.to raise_error(Rosegold::Physics::MovementStuck)
        expect(bot.location.z).to be_close(FLUSH_Z, 1e-6)

        bot.move_to 2.5, bot.location.z
        bot.wait_ticks 5

        expect(bot.location.x).to be_close(2.5, 0.05)
        expect(bot.location.z).to be_close(FLUSH_Z, 1e-6)

        admin.setblock 2, -60, 2, "air"
        bot.wait_tick
      end
    end
  end

  it "slides along the south (max.z) face and parks at the vanilla flush coordinate" do
    south_flush_z = 3.0 + 0.30000001192092896

    admin.setblock 2, -60, 2, "melon"
    admin.wait_tick

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1.9, -60, 3.5
        bot.wait_ticks 3

        expect { bot.move_to 1.9, 2.0 }.to raise_error(Rosegold::Physics::MovementStuck)
        expect(bot.location.z).to be_close(south_flush_z, 1e-6)

        bot.move_to 2.5, bot.location.z
        bot.wait_ticks 5

        expect(bot.location.x).to be_close(2.5, 0.05)
        expect(bot.location.z).to be_close(south_flush_z, 1e-6)

        admin.setblock 2, -60, 2, "air"
        bot.wait_tick
      end
    end
  end

  it "walks along the face under raw input without server snap-back" do
    admin.setblock 2, -60, 2, "melon"
    admin.wait_tick

    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp 1.9, -60, FLUSH_Z
        bot.wait_ticks 3

        bot.yaw = -90.0 # face +X, parallel to the melon's north face
        bot.keys.press Rosegold::MovementKeys::Key::Forward
        20.times { bot.wait_tick }
        bot.keys.release_all
        bot.wait_ticks 5

        admin.setblock 2, -60, 2, "air"
        bot.wait_tick

        expect(bot.location.x).to be > 4.0
        expect(bot.location.z).to be_close(FLUSH_Z, 1e-4)
      end
    end
  end
end
