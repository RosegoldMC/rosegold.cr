require "../src/rosegold"

# Example of how to use the Rosegold proxy server
# This allows a Minecraft client to connect and control a rosegold bot

# Configuration
MINECRAFT_SERVER_HOST = "localhost"
MINECRAFT_SERVER_PORT = 25565
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 25566

puts "🤖 Starting Rosegold Proxy Example"

# Create the bot client (offline mode for testing)
bot = Rosegold::Client.new(
  MINECRAFT_SERVER_HOST, 
  MINECRAFT_SERVER_PORT,
  offline: {
    uuid: "12345678-1234-5678-9012-123456789012", 
    username: "RosegoldBot"
  }
)

# Create the proxy server
proxy = Rosegold::ProxyServer.new(PROXY_HOST, PROXY_PORT)

# Attach the proxy to the bot
bot.attach_proxy(proxy)

# Start the proxy server
proxy.start

puts "✅ Proxy server started on #{PROXY_HOST}:#{PROXY_PORT}"
puts "📋 Instructions:"
puts "   1. Connect your Minecraft client to #{PROXY_HOST}:#{PROXY_PORT}"
puts "   2. Use /rosegold help to see available commands"
puts "   3. Use /rosegold lock to let the bot take control"
puts "   4. Use /rosegold unlock to take control yourself"
puts ""

# Connect the bot to the Minecraft server
puts "🔄 Connecting bot to Minecraft server..."
begin
  bot.connect
  
  puts "✅ Bot connected to server!"
  puts "🎮 You can now connect your Minecraft client to the proxy"
  
  # Keep the proxy running
  sleep
rescue e
  puts "❌ Failed to connect bot to server: #{e}"
  puts "📝 Make sure the Minecraft server is running and accessible"
  
  # Keep proxy running even if bot connection fails
  # This allows testing the proxy interface
  puts "🔄 Proxy remains active for testing commands"
  sleep
ensure  
  proxy.stop
  puts "🛑 Proxy server stopped"
end