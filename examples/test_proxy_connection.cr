require "../src/rosegold"

# Simple test to verify proxy connection handling works
puts "🧪 Testing Proxy Connection Handling"

# Create a proxy server
proxy = Rosegold::ProxyServer.new("127.0.0.1", 25570)

# Create a mock bot (doesn't need to connect to real server for this test)
bot = Rosegold::Client.new(
  "dummy-server.com", 25565,
  offline: {
    uuid: "12345678-1234-5678-9012-123456789012",
    username: "TestBot"
  }
)

# Attach proxy to bot
bot.attach_proxy(proxy)

# Start proxy server
puts "✅ Starting proxy server on 127.0.0.1:25570"
proxy.start

puts "🔧 Proxy Configuration:"
puts "   - Lockout active: #{proxy.lockout_active?}"
puts "   - Bot connected: #{proxy.bot_connected?}"
puts ""
puts "📋 Connection Instructions:"
puts "   1. The proxy server is now running on 127.0.0.1:25570"
puts "   2. Try connecting with a Minecraft client"  
puts "   3. You should be able to complete the login process"
puts "   4. Use /rosegold help to see available commands"
puts ""
puts "⏹️  Press Ctrl+C to stop the proxy server"

# Keep running until interrupted
begin
  sleep
rescue e
  puts "\n🛑 Stopping proxy server..."
ensure
  proxy.stop
  puts "✅ Proxy server stopped successfully"
end