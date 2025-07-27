require "./src/rosegold"

# Capture a real JoinGame packet from server connection
puts "🔍 Capturing JoinGame packet from server..."

MINECRAFT_SERVER_HOST = "localhost"
MINECRAFT_SERVER_PORT = 25565

# Create bot to capture real server packets
bot = Rosegold::Client.new(
  MINECRAFT_SERVER_HOST, 
  MINECRAFT_SERVER_PORT,
  offline: {
    uuid: "12345678-1234-5678-9012-123456789012", 
    username: "JoinGameCapture"
  }
)

# Variable to store the captured JoinGame packet
captured_join_game : Bytes? = nil

# Hook into packet reading to capture JoinGame
bot.on Rosegold::Clientbound::JoinGame do |join_game_packet|
  puts "✅ Captured JoinGame packet!"
  puts "Entity ID: #{join_game_packet.entity_id}"
  puts "Hardcore: #{join_game_packet.hardcore?}"
  puts "Dimensions: #{join_game_packet.dimension_names}"
  puts "Max players: #{join_game_packet.max_players}"
  puts "View distance: #{join_game_packet.view_distance}"
  puts "Dimension type: #{join_game_packet.dimension_type}"
  puts "Dimension name: #{join_game_packet.dimension_name}"
  puts "Gamemode: #{join_game_packet.gamemode}"
  
  # Get the raw packet bytes
  packet_bytes = join_game_packet.write
  puts "Packet size: #{packet_bytes.size} bytes"
  puts "Packet bytes: #{packet_bytes.map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"
  
  # Save to fixture file
  Dir.mkdir_p("spec/fixtures/packets/clientbound")
  File.write("spec/fixtures/packets/clientbound/join_game_real.bin", packet_bytes)
  puts "💾 Saved to spec/fixtures/packets/clientbound/join_game_real.bin"
  
  captured_join_game = packet_bytes
  
  # Disconnect after capturing
  spawn do
    sleep 1.second
    bot.connection?.try(&.disconnect(Rosegold::Chat.new("Captured packet")))
  end
end

begin
  puts "🔗 Connecting to server to capture JoinGame packet..."
  bot.connect
  
  # Wait for JoinGame packet
  timeout = 30
  while captured_join_game.nil? && timeout > 0
    sleep 1.second
    timeout -= 1
    if timeout % 5 == 0
      puts "⏳ Waiting for JoinGame packet... #{timeout}s remaining"
    end
  end
  
  if captured_join_game
    puts "🎉 Successfully captured JoinGame packet!"
  else
    puts "❌ Failed to capture JoinGame packet within timeout"
    exit 1
  end
  
rescue e
  puts "❌ Failed to connect or capture packet: #{e}"
  exit 1
end