require "../src/rosegold"

# Example showing how to use the spectate server with a real Minecraft server
puts "🚀 Rosegold Spectate Server with Real Server Example"

# Configuration - CHANGE THESE to match your setup
MINECRAFT_SERVER_HOST = "localhost" # Change to your server's IP
MINECRAFT_SERVER_PORT = 25565       # Change to your server's port
SPECTATE_HOST         = "127.0.0.1"
SPECTATE_PORT         = 25566

puts "📋 Configuration:"
puts "   Minecraft Server: #{MINECRAFT_SERVER_HOST}:#{MINECRAFT_SERVER_PORT}"
puts "   Spectate Server: #{SPECTATE_HOST}:#{SPECTATE_PORT}"
puts ""

# Create the bot client
client = Rosegold::Client.new(
  MINECRAFT_SERVER_HOST,
  MINECRAFT_SERVER_PORT,
  offline: {
    uuid:     "12345678-1234-5678-9012-123456789012",
    username: "SpectateBot",
  }
)
bot = Rosegold::Bot.new(client)

# Create the spectate server
spectate_server = Rosegold::SpectateServer.new(SPECTATE_HOST, SPECTATE_PORT)

# Attach the spectate server to the bot
client.attach_spectate_server(spectate_server)

# Start the spectate server
spectate_server.start
puts "✅ Spectate server started on #{SPECTATE_HOST}:#{SPECTATE_PORT}"

# Connect the bot to the Minecraft server
puts "🔄 Connecting bot to Minecraft server #{MINECRAFT_SERVER_HOST}:#{MINECRAFT_SERVER_PORT}..."

begin
  client.join_game

  puts "✅ Bot connected to server successfully!"
  puts ""
  puts "🎮 Ready for client connections!"
  puts "📋 Instructions:"
  puts "   1. Connect your Minecraft client to #{SPECTATE_HOST}:#{SPECTATE_PORT}"
  puts "   2. You should join the same world as the bot"
  puts "   3. Use /rosegold help to see spectate commands"
  puts "   4. Use /rosegold lock to let the bot take control"
  puts "   5. Use /rosegold unlock to take control yourself"
  puts ""
  puts "⚠️  The bot and client will share the same player - this is expected!"
  puts ""
  puts "⏹️  Press Ctrl+C to stop"

  spawn do
    while bot.connected?
      bot.move_to rand(-10..10), rand(-10..10)
    end
  end

  # Keep the spectate server running
  sleep
rescue e
  puts "❌ Failed to connect bot to server: #{e.message}"
  puts ""
  puts "🔧 Troubleshooting:"
  puts "   • Make sure Minecraft server is running on #{MINECRAFT_SERVER_HOST}:#{MINECRAFT_SERVER_PORT}"
  puts "   • Check if server allows offline-mode connections"
  puts "   • Verify server is accessible from this machine"
  puts "   • Try connecting with a regular Minecraft client first"
  puts ""
  puts "🔄 Spectate server remains active but clients will be disconnected until bot connects"

  # Keep spectate server running for testing
  sleep
ensure
  spectate_server.stop
  puts "🛑 Spectate server and bot stopped"
end
