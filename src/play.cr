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
          puts bot.player.feet
        when "\\pitch"
          if command.size > 1
            bot.pitch = command[1].to_f
          else
            puts bot.pitch
          end
        when "\\yaw"
          if command.size > 1
            bot.yaw = command[1].to_f
          else
            puts bot.yaw
          end
        when "\\move"
          bot.move_to command[1].to_f, command[2].to_f, command[3].to_f
        when "\\jump"
          bot.jump
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
