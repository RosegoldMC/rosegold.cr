#!/usr/bin/env crystal

require "../src/rosegold"

# Test script to demonstrate proxy functionality
# This shows how the proxy would work with a real connection

puts "Rosegold Proxy Test"
puts "=================="

# Create a bot client in offline mode for testing
bot_client = Rosegold::Client.new("localhost", 25565, offline: {
  uuid: "550e8400-e29b-41d4-a716-446655440000", 
  username: "TestBot"
})

puts "✓ Created bot client: #{bot_client.player.username}"

# Start the proxy
proxy = bot_client.start_proxy("localhost", 25567)
if proxy.nil?
  puts "❌ Failed to start proxy"
  exit 1
end
puts "✓ Started proxy on localhost:25567"

# Demonstrate proxy features
puts "\nProxy Information:"
puts "  Host: #{proxy.host}"
puts "  Port: #{proxy.port}"
puts "  Locked: #{proxy.locked}"
puts "  Connected clients: #{proxy.connected_clients.size}"

# Test locking
proxy.lock
puts "✓ Proxy locked"
puts "  Locked: #{proxy.locked}"

proxy.unlock  
puts "✓ Proxy unlocked"
puts "  Locked: #{proxy.locked}"

# Stop the proxy
bot_client.stop_proxy
puts "✓ Proxy stopped"

puts "\n🎉 Proxy test completed successfully!"
puts "\nTo test with a real Minecraft client:"
puts "1. Start your bot: bot = Rosegold::Bot.join_game('server.net')"
puts "2. Start proxy: bot.start_proxy()"
puts "3. Connect your Minecraft client to localhost:25566"