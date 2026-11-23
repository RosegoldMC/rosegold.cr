require "../spec_helper"

Spectator.describe "Rosegold::Bot ice road physics" do
  it "should achieve high speed ice road movement" do
    admin.kill_entities

    base_y = -61
    start_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, 0.5)
    test_distance = 30.0
    end_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, test_distance)

    admin.fill 20, base_y, 0, 20, base_y, 40, "ice"
    admin.fill 20, base_y + 1, 0, 20, base_y + 1, 40, "stone_button[face=floor]"
    admin.fill 20, base_y + 2, 0, 20, base_y + 2, 40, "oak_trapdoor[half=top]"
    admin.fill 20, base_y + 3, 0, 20, base_y + 3, 40, "obsidian"
    admin.wait_tick
    test_client = client
    test_client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        admin.tp start_pos.x, start_pos.y, start_pos.z
        admin.give "baked_potato", 64
        bot.wait_ticks 15

        bot.eat!

        initial_position = bot.location

        measurement_start = 15.0
        measurement_end = 25.0
        start_time : Time? = nil
        average_speed = nil

        movement_deadline = Time.instant + 15.seconds
        move_done = false
        move_error : Exception? = nil
        spawn do
          bot.move_to(end_pos.x, end_pos.z, stuck_timeout_ticks: 60)
        rescue ex
          move_error = ex
        ensure
          move_done = true
        end

        until move_done
          remaining = movement_deadline - Time.instant
          tick = remaining.positive? && client.connected? && client.wait_tick(Math.min(remaining, 1.second))
          break if move_done && move_error
          raise "Ice road client disconnected during movement" unless client.connected?
          raise "Ice road movement did not finish within 15 seconds" if !move_done && Time.instant >= movement_deadline
          raise "Timed out waiting for an ice road movement tick" unless tick
          next if average_speed

          current_z = bot.location.z

          if start_time.nil? && current_z >= measurement_start
            start_time = Time.utc
          end

          if start_time_value = start_time
            if current_z >= measurement_end
              elapsed = Time.utc - start_time_value
              distance = measurement_end - measurement_start
              average_speed = distance / elapsed.total_seconds
              Log.info { "Ice road speed: #{average_speed.round(1)} m/s over #{distance}m" }
              next
            end
          end

          distance_remaining = (end_pos.z - current_z).abs
          if distance_remaining > 10.0
            bot.sprint
            bot.start_jump
          else
            bot.sprint(false)
          end
        end

        if error = move_error
          raise error
        end

        average_speed ||= 0.0
        distance_traveled = bot.location.z - initial_position.z

        expect(bot.location.x).to be_close(start_pos.x, 1.0)
        expect(bot.location.z).to be >= 25.0
        expect(average_speed).to be >= 15.0
        expect(average_speed).to be <= 27.0

        Log.info { "Ice road speed test: #{average_speed.round(2)} m/s over #{distance_traveled.round(1)}m" }
      ensure
        bot.stop_moving if move_done == false
      end
    end
  ensure
    begin
      test_client.try &.connection?.try &.disconnect("End of ice road spec")
    rescue ex
      Log.warn(exception: ex) { "Could not disconnect the ice road spec client" }
    end
  end
end
