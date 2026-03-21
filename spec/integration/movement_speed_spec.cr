require "../spec_helper"

Spectator.describe "Rosegold::Bot movement speeds" do
  before_all do
    admin.setup_arena
    admin.wait_ticks 19
  end

  it "should have correct movement speeds for sneak, walk, and sprint" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        bot.wait_ticks 5
        admin.tp 0, -60, 0
        bot.wait_ticks 10

        bot.sneak(true)
        bot.wait_ticks 2
        start_time = Time.instant
        bot.move_to 5, 0
        sneak_time = Time.instant - start_time
        sneak_speed = 5.0 / sneak_time.total_seconds

        admin.tp 0, -60, 0
        bot.wait_ticks 10
        bot.sneak(false)
        bot.wait_ticks 2

        start_time = Time.instant
        bot.move_to 5, 0
        walk_time = Time.instant - start_time
        walk_speed = 5.0 / walk_time.total_seconds

        admin.tp 0, -60, 0
        bot.wait_ticks 10

        bot.sprint(true)
        bot.wait_ticks 2
        start_time = Time.instant
        bot.move_to 5, 0
        sprint_time = Time.instant - start_time
        sprint_speed = 5.0 / sprint_time.total_seconds

        expect(sneak_speed).to be_close(walk_speed * 0.3, walk_speed * 0.1)

        expect(sprint_speed).to be_close(walk_speed * 1.3, walk_speed * 0.1)

        expect(walk_speed).to be >= 3.0
        expect(walk_speed).to be <= 6.0

        bot.sprint(false)
      end
    end
  end
end
