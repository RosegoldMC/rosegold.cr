#!/usr/bin/env crystal

require "../src/rosegold"

# Simple example demonstrating the proxy functionality
# This creates a bot, starts a proxy, and shows how to use it

bot = Rosegold::Bot.join_game("localhost:25565").try do |bot|
  # Start the proxy server on port 25566
  proxy = bot.start_proxy("localhost", 25566)
  
  puts "Bot connected to server!"
  puts "Proxy started on localhost:25566"
  puts "Connect your Minecraft client to localhost:25566 to control the bot"
  puts "Press Ctrl+C to stop"
  
  # Simple bot behavior
  spawn do
    while bot.connected?
      sleep 5
      bot.chat "I'm a bot with proxy support!"
    end
  end
  
  # Keep the bot running
  loop do
    sleep 1
    break unless bot.connected?
  end
end