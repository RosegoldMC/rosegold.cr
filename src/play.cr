require "./rosegold"

def show_help
  puts "Rosegold v#{Rosegold::VERSION}"
  puts "~"*20
  puts "\\help - This help screen"
  puts "\\position - Displays the current coordinates of the player"
end

Rosegold::Client.new("minecraft.grepscraft.com", 25565).start do |client|
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
