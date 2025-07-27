require "../src/rosegold"

# Example showing how to use the proxy with a real Minecraft server
puts "🚀 Rosegold Proxy with Real Server Example"

# Configuration - CHANGE THESE to match your setup
MINECRAFT_SERVER_HOST = "localhost"  # Change to your server's IP
MINECRAFT_SERVER_PORT = 25565       # Change to your server's port
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 25566

puts "📋 Configuration:"
puts "   Minecraft Server: #{MINECRAFT_SERVER_HOST}:#{MINECRAFT_SERVER_PORT}"
puts "   Proxy Server: #{PROXY_HOST}:#{PROXY_PORT}"
puts ""

# Create the bot client
bot = Rosegold::Client.new(
  MINECRAFT_SERVER_HOST, 
  MINECRAFT_SERVER_PORT,
  offline: {
    uuid: "12345678-1234-5678-9012-123456789012", 
    username: "ProxyBot"
  }
)

# Create the proxy server
proxy = Rosegold::ProxyServer.new(PROXY_HOST, PROXY_PORT)

# Attach the proxy to the bot
bot.attach_proxy(proxy)

# Start the proxy server
proxy.start
puts "✅ Proxy server started on #{PROXY_HOST}:#{PROXY_PORT}"

# Connect the bot to the Minecraft server
puts "🔄 Connecting bot to Minecraft server #{MINECRAFT_SERVER_HOST}:#{MINECRAFT_SERVER_PORT}..."

begin
  bot.connect
  
  puts "✅ Bot connected to server successfully!"
  puts ""
  puts "🎮 Ready for client connections!"
  puts "📋 Instructions:"
  puts "   1. Connect your Minecraft client to #{PROXY_HOST}:#{PROXY_PORT}"
  puts "   2. You should join the same world as the bot"
  puts "   3. Use /rosegold help to see proxy commands"
  puts "   4. Use /rosegold lock to let the bot take control"
  puts "   5. Use /rosegold unlock to take control yourself"
  puts ""
  puts "⚠️  The bot and client will share the same player - this is expected!"
  puts ""
  puts "⏹️  Press Ctrl+C to stop"
  
  # Keep the proxy running
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
  puts "🔄 Proxy remains active but clients will be disconnected until bot connects"
  
  # Keep proxy running for testing
  sleep
  
ensure  
  proxy.stop
  puts "🛑 Proxy and bot stopped"
end