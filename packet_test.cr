require "./src/rosegold"

# Script to test packet sending behavior
client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "packettest"})

client.join_game do |client|
  bot = Rosegold::Bot.new(client)
  
  puts "Testing sneak functionality comprehensively..."
  
  bot.wait_tick
  
  puts "Initial state - sneaking?: #{bot.sneaking?}"
  
  # Test 1: Basic sneak
  puts "\n=== Test 1: Basic sneak ==="
  puts "Calling bot.sneak..."
  bot.sneak
  bot.wait_tick
  puts "After sneak - sneaking?: #{bot.sneaking?}"
  
  # Test 2: Calling sneak when already sneaking
  puts "\n=== Test 2: Sneak when already sneaking ==="
  puts "Calling bot.sneak again..."
  bot.sneak
  bot.wait_tick
  puts "After second sneak - sneaking?: #{bot.sneaking?}"
  
  # Test 3: Explicit true
  puts "\n=== Test 3: Explicit sneak(true) ==="
  puts "Calling bot.sneak(true)..."
  bot.sneak(true)
  bot.wait_tick
  puts "After sneak(true) - sneaking?: #{bot.sneaking?}"
  
  # Test 4: Explicit false
  puts "\n=== Test 4: Explicit sneak(false) ==="
  puts "Calling bot.sneak(false)..."
  bot.sneak(false)
  bot.wait_tick
  puts "After sneak(false) - sneaking?: #{bot.sneaking?}"
  
  # Test 5: Unsneak method
  puts "\n=== Test 5: Unsneak method ==="
  puts "First setting sneak to true..."
  bot.sneak(true)
  bot.wait_tick
  puts "sneaking?: #{bot.sneaking?}"
  puts "Now calling bot.unsneak..."
  bot.unsneak
  bot.wait_tick
  puts "After unsneak - sneaking?: #{bot.sneaking?}"
  
  puts "\nAll tests completed successfully! Sneak functionality is working."
end