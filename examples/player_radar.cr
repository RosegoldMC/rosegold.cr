require "../src/rosegold"

include Rosegold

# Example script demonstrating the player radar functionality
# Usage: crystal run examples/player_radar.cr

def show_help
  puts "Player Radar Demo"
  puts "=================="
  puts "\\help - This help screen"
  puts "\\radar - Show nearby players"
  puts "\\radar <distance> - Show players within specified distance"
  puts "\\position - Displays the current coordinates of the player"
  puts "\\quit - Exit the program"
end

puts "Enter server address (or press Enter for localhost):"
server = gets.to_s.strip
server = "localhost" if server.empty?

begin
  Client.new(server).join_game do |client|
    bot = Rosegold::Bot.new client
    
    show_help
    
    while input = gets
      next if input.empty?
      
      command = input.split(" ")
      case command.first
      when "\\help"
        show_help
      when "\\position"
        puts "Bot position: #{bot.feet}"
      when "\\radar"
        max_distance = command.size > 1 ? command[1].to_f64 : Float64::INFINITY
        nearby_players = bot.radar(max_distance)
        
        if nearby_players.empty?
          if max_distance == Float64::INFINITY
            puts "No other players detected."
          else
            puts "No players within #{max_distance} blocks."
          end
        else
          puts "Nearby players:"
          nearby_players.each do |player_info|
            distance = player_info[:distance].round(2)
            bearing = player_info[:bearing].round(1)
            uuid = player_info[:uuid]
            pos = player_info[:position]
            
            puts "  Player #{uuid}"
            puts "    Distance: #{distance} blocks"
            puts "    Bearing: #{bearing}° (0°=North, 90°=East, 180°=South, 270°=West)"
            puts "    Position: #{pos.x.round(2)}, #{pos.y.round(2)}, #{pos.z.round(2)}"
            puts
          end
        end
      when "\\quit"
        puts "Goodbye!"
        break
      else
        # Send chat message unless it's a command
        bot.chat input unless input.starts_with? "\\"
      end
    end
  end
rescue ex
  puts "Error: #{ex.message}"
  puts "Make sure the server is running and accessible."
end