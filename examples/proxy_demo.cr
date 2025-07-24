#!/usr/bin/env crystal

require "../src/rosegold"

# Demo script showing how to use the proxy feature
# This demonstrates connecting a bot to a server and allowing clients to control it

puts "Rosegold Proxy Demo"
puts "=================="
puts

# Check command line arguments
if ARGV.empty?
  puts "Usage: crystal run examples/proxy_demo.cr [server:port]"
  puts "Example: crystal run examples/proxy_demo.cr play.example.net:25565"
  puts
  puts "This will:"
  puts "1. Connect a rosegold bot to the specified server"
  puts "2. Start a proxy server on localhost:25566"
  puts "3. Allow Minecraft clients to connect to localhost:25566 to control the bot"
  exit 1
end

server_address = ARGV[0]
proxy_port = 25566

puts "1. Connecting bot to #{server_address}..."

begin
  bot = Rosegold::Bot.join_game(server_address)
  
  puts "✓ Bot connected successfully!"
  puts "  UUID: #{bot.uuid}"
  puts "  Username: #{bot.username}" 
  puts "  Position: #{bot.feet}"
  puts
  
  puts "2. Starting proxy server on localhost:#{proxy_port}..."
  proxy = bot.start_proxy("localhost", proxy_port)
  
  puts "✓ Proxy server started!"
  puts
  puts "🎮 Ready! Connect your Minecraft client to:"
  puts "   Server: localhost:#{proxy_port}"
  puts
  puts "What you can do:"
  puts "- Move around and the bot will follow your movements"
  puts "- Type in chat and the bot will send those messages"
  puts "- Interact with the world through the bot"
  puts
  puts "Press Ctrl+C to stop the bot and proxy"
  puts
  
  # Simple bot loop with status updates
  loop do
    sleep 10
    
    if bot.connected?
      puts "[#{Time.local}] Bot status: Connected, Position: #{bot.feet}, Health: #{bot.health}/20"
      
      if proxy.connected_clients.any?
        puts "  📱 #{proxy.connected_clients.size} client(s) connected to proxy"
      else
        puts "  ⏳ Waiting for clients to connect to proxy..."
      end
    else
      puts "❌ Bot disconnected: #{bot.disconnect_reason}"
      break
    end
  end
  
rescue e : Rosegold::Client::NotConnected
  puts "❌ Failed to connect to server: #{e.message}"
  exit 1
rescue e : Exception
  puts "❌ Error: #{e.message}"
  exit 1
ensure
  puts "\n🛑 Shutting down..."
end