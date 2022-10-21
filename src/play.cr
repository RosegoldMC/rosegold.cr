require "./rosegold"

def show_help
  puts "Rosegold v#{Rosegold::VERSION}"
  puts "~"*20
  puts "\\help - This help screen"
  puts "\\position - Displays the current coordinates of the player"
end

Rosegold::Client.new("localhost", 25565).start do |bot|
  show_help

  spawn do
    loop do
      bot.move_to rand(-10..10), -60, rand(-10..10)
      sleep 3
    end
  end

  loop do
    gets.try do |input|
      next if input.empty?

      if input.starts_with? "\\"
        command = input.split(" ")
        case command.first
        when "\\help"
          show_help
        when "\\position"
          puts bot.feet
        when "\\pitch"
          if command.size > 1
            bot.look_by bot.look.with_pitch_deg command[1].to_f.to_f32
          else
            puts bot.look.pitch_deg
          end
        when "\\yaw"
          if command.size > 1
            bot.look_by bot.look.with_yaw_deg command[1].to_f.to_f32
          else
            puts bot.look.yaw_deg
          end
        when "\\move"
          spawn do
            location = Rosegold::Vec3d.new command[1].to_f, bot.feet.y, command[3].to_f
            begin
              bot.move_to location
              puts "Arrived at #{bot.feet}"
            rescue ex
              puts "Movement to #{location} failed:"
              puts ex
            end
          end
        when "\\jump"
          bot.start_jump
        when "\\debug"
          Log.setup :debug
        when "\\trace"
          Log.setup :trace
        end

        next
      end

      bot.chat input
    end
  end
end