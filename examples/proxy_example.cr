require "../src/rosegold"

# Example of how to use the Rosegold proxy server
# This allows a Minecraft client to connect and control a rosegold bot

# Configuration
MINECRAFT_SERVER_HOST = "localhost"
MINECRAFT_SERVER_PORT = 25565
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 25566

puts "🤖 Rosegold Proxy - Testing Mode Example"
puts "⚠️  This example demonstrates proxy connection handling without a real server"
puts ""

# Create the bot client (offline mode for testing)
# NOTE: This bot is NOT connected to a real server in this example
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
puts ""
puts "📋 Test Instructions:"
puts "   1. Connect your Minecraft client to #{PROXY_HOST}:#{PROXY_PORT}"
puts "   2. Client will complete login process"  
puts "   3. Client will be disconnected with 'No bot server connected' message"
puts "   4. This demonstrates the proxy connection handling works correctly"
puts ""
puts "💡 For real usage with server forwarding, use examples/proxy_with_server.cr"
puts ""
puts "⏹️  Press Ctrl+C to stop"

# DON'T connect the bot - this is for testing proxy connection handling only
# In production, you would call bot.connect here

# Keep the proxy running for testing
begin
  sleep
rescue e
  puts "\n🛑 Stopping proxy server..."
ensure  
  proxy.stop
  puts "✅ Proxy server stopped"
end