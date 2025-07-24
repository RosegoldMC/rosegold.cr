require "../src/rosegold"

# Debug version of proxy to see what packets are being received
puts "🔍 Debug Proxy - Packet Analysis Mode"

# Create a proxy server
proxy = Rosegold::ProxyServer.new("127.0.0.1", 25566)

# Create a mock bot (doesn't need to connect to real server)
bot = Rosegold::Client.new(
  "dummy-server.com", 25565,
  offline: {
    uuid: "12345678-1234-5678-9012-123456789012",
    username: "DebugBot"
  }
)

# Attach proxy to bot
bot.attach_proxy(proxy)

# Enable trace-level logging to see all packet details
Log.setup_from_env(default_level: :trace)

# Start proxy server
puts "✅ Starting debug proxy server on 127.0.0.1:25566"
puts "🔍 All packet details will be logged with TRACE level"
puts "📋 Instructions:"
puts "   1. Connect your Minecraft client to 127.0.0.1:25566"
puts "   2. Watch the logs to see which packets cause issues"
puts "   3. The bundle_item_selected error should be resolved"
puts ""
proxy.start

puts "⏹️  Press Ctrl+C to stop the proxy server"

# Keep running until interrupted
begin
  sleep
rescue e
  puts "\n🛑 Stopping proxy server..."
ensure
  proxy.stop
  puts "✅ Debug proxy server stopped"
end