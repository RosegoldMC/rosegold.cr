require "./src/rosegold"

# Simple script to test bot.sneak functionality
client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "sneaktest"})

client.join_game do |client|
  bot = Rosegold::Bot.new(client)
  
  puts "Starting sneak test..."
  
  # Give the bot a second to be fully ready
  bot.wait_tick
  bot.wait_tick
  
  puts "Initial sneaking state: #{bot.sneaking?}"
  
  # Call sneak
  puts "Calling bot.sneak..."
  bot.sneak
  
  bot.wait_tick
  puts "After calling bot.sneak: #{bot.sneaking?}"
  
  # Call unsneak
  puts "Calling bot.unsneak..."
  bot.unsneak
  
  bot.wait_tick
  puts "After calling bot.unsneak: #{bot.sneaking?}"
  
  # Test explicit sneak true/false
  puts "Calling bot.sneak(true)..."
  bot.sneak(true)
  
  bot.wait_tick
  puts "After calling bot.sneak(true): #{bot.sneaking?}"
  
  puts "Calling bot.sneak(false)..."
  bot.sneak(false)
  
  bot.wait_tick
  puts "After calling bot.sneak(false): #{bot.sneaking?}"
  
  puts "Sneak test completed successfully!"
end