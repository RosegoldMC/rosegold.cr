require "../spec_helper"

Spectator.describe "Rosegold::Bot ice road physics" do
  # Ice road technique: sprint + jump repeatedly on ice for high speed travel
  # Expected speed: ~18 m/s (much faster than normal sprint speed of ~5.6 m/s)

  it "should achieve high speed ice road movement" do
    client.join_game do |client|
      Rosegold::Bot.new(client).try do |bot|
        # Test parameters - shorter test
        base_y = -61
        start_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, 0.5)
        test_distance = 30.0
        end_pos = Rosegold::Vec3d.new(20.5, base_y + 1.0, test_distance)

        # Build shorter ice road
        bot.chat "/fill 20 #{base_y} 0 20 #{base_y} 40 minecraft:ice"
        bot.chat "/fill 20 #{base_y + 1} 0 20 #{base_y + 1} 40 minecraft:stone_button[face=floor]"
        bot.chat "/fill 20 #{base_y + 2} 0 20 #{base_y + 2} 40 minecraft:oak_trapdoor[half=top]"
        bot.chat "/fill 20 #{base_y + 3} 0 20 #{base_y + 3} 40 minecraft:obsidian"

        # Position bot at start
        bot.chat "/tp #{start_pos.x} #{start_pos.y} #{start_pos.z}"
        bot.wait_ticks 5

        initial_position = bot.feet

        # Measure speed over smaller window: blocks 15-25 (10 block sample)
        measurement_start = 15.0
        measurement_end = 25.0
        start_time : Time? = nil

        # Execute ice road movement
        move_done = false
        spawn do
          bot.move_to(end_pos.x, end_pos.z, stuck_timeout_ticks: 60)
          move_done = true
        end

        # Apply ice road technique and measure speed in the middle section
        until move_done
          bot.wait_ticks 1
          current_z = bot.feet.z

          # Start timing when entering measurement zone
          if start_time.nil? && current_z >= measurement_start
            start_time = Time.utc
          end

          # Stop and calculate when exiting measurement zone
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

        # Wait for movement to complete
        until move_done
          bot.wait_ticks 1
        end

        # Set defaults if measurement failed
        average_speed ||= 0.0
        distance_traveled = bot.feet.z - initial_position.z

        # Assertions
        expect(bot.feet.x).to be_close(start_pos.x, 1.0) # Stayed on track
        expect(bot.feet.z).to be >= 25.0                 # Reached measurement endpoint
        expect(average_speed).to be >= 15.0              # Minimum speed threshold
        expect(average_speed).to be <= 27.0              # Maximum reasonable speed

        Log.info { "Ice road speed test: #{average_speed.round(2)} m/s over #{distance_traveled.round(1)}m" }
      end
    end
  end
end
