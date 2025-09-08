require "../spec_helper"

Spectator.describe "Rosegold::Bot ice road physics" do
  it "should achieve high speed ice road movement" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        base_y = -61
        start_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, 0.5)
        test_distance = 30.0
        end_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, test_distance)

        bot.chat "/fill 20 #{base_y} 0 20 #{base_y} 40 minecraft:ice"
        bot.chat "/fill 20 #{base_y + 1} 0 20 #{base_y + 1} 40 minecraft:stone_button[face=floor]"
        bot.chat "/fill 20 #{base_y + 2} 0 20 #{base_y + 2} 40 minecraft:oak_trapdoor[half=top]"
        bot.chat "/fill 20 #{base_y + 3} 0 20 #{base_y + 3} 40 minecraft:obsidian"

        bot.chat "/tp #{start_pos.x} #{start_pos.y} #{start_pos.z}"
        bot.chat "/give @s minecraft:baked_potato 64"
        bot.wait_ticks 5

        bot.eat!

        initial_position = bot.feet

        measurement_start = 15.0
        measurement_end = 25.0
        start_time : Time? = nil

        move_done = false
        spawn do
          bot.move_to(end_pos.x, end_pos.z, stuck_timeout_ticks: 60)
          move_done = true
        end

        until move_done
          bot.wait_ticks 1
          current_z = bot.feet.z

          if start_time.nil? && current_z >= measurement_start
            start_time = Time.utc
          end

          if start_time_value = start_time
            if current_z >= measurement_end
              elapsed = Time.utc - start_time_value
              distance = measurement_end - measurement_start
              average_speed = distance / elapsed.total_seconds
              Log.info { "Ice road speed: #{average_speed.round(1)} m/s over #{distance}m" }
              break
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

        until move_done
          bot.wait_ticks 1
        end

        average_speed ||= 0.0
        distance_traveled = bot.feet.z - initial_position.z

        expect(bot.feet.x).to be_close(start_pos.x, 1.0)
        expect(bot.feet.z).to be >= 25.0
        expect(average_speed).to be >= 15.0
        expect(average_speed).to be <= 27.0

        Log.info { "Ice road speed test: #{average_speed.round(2)} m/s over #{distance_traveled.round(1)}m" }
      end
    end
  end
end
