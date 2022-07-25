require "./rosegold"

def show_help
  puts "Rosegold v#{Rosegold::VERSION}"
  puts "~"*20
  puts "\\help - This help screen"
  puts "\\position - Displays the current coordinates of the player"
end

Rosegold::Client.new("localhost", 25565).start do |client|
  show_help
  loop do
    gets.try do |input|
      next if input.empty?

      if input.starts_with? "\\"
        command = input.split(" ")
        case command.first
        when "\\help"
          show_help
        when "\\position"
          puts client.player.feet
        when "\\pitch"
          if command.size > 1
            client.player.pitch = command[1].to_f
          else
            puts client.player.pitch
          end
        when "\\yaw"
          if command.size > 1
            client.player.yaw = command[1].to_f
          else
            puts client.player.yaw
          end
        when "\\debug"
          Log.setup :debug
        when "\\trace"
          Log.setup :trace
        end

        next
      end

      client.queue_packet Rosegold::Serverbound::Chat.new input
    end
  end
end
