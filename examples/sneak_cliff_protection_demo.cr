require "../src/rosegold"

# Simple demonstration of sneak cliff protection
# This shows how the feature prevents movement when sneaking near cliffs

# Create a simple mock setup to demonstrate cliff protection
dimension = Rosegold::Dimension.new
client = Rosegold::Client.new("demo")

# Set up player state for demonstration
client.player.feet = Rosegold::Vec3d.new(5.0, 10.0, 5.0)
client.player.sneaking = true

# Create physics instance  
physics = Rosegold::Physics.new(client)

puts "=== Sneak Cliff Protection Demo ==="
puts "Player position: #{client.player.feet}"
puts "Player sneaking: #{client.player.sneaking?}"
puts ""

# Test different movement scenarios
test_positions = [
  Rosegold::Vec3d.new(5.5, 10.0, 5.0),   # Small movement, should be safe
  Rosegold::Vec3d.new(6.0, 10.0, 5.0),   # Larger movement, might trigger protection
  Rosegold::Vec3d.new(10.0, 10.0, 5.0),  # Large movement, would likely trigger protection
]

test_positions.each_with_index do |pos, i|
  puts "Test #{i + 1}: Moving to #{pos}"
  
  # Simulate what would happen in velocity_for_inputs
  move_horiz_vec = (pos - client.player.feet).with_y(0)
  puts "  Intended movement vector: #{move_horiz_vec}"
  puts "  Movement distance: #{move_horiz_vec.length}"
  
  if client.player.sneaking? && move_horiz_vec.length > Rosegold::Physics::VERY_CLOSE
    puts "  Sneaking detected, checking cliff protection..."
    
    # Note: In a real scenario, this would check actual block data
    # For demo purposes, we'll simulate different outcomes
    case i
    when 0
      puts "  ✓ Movement allowed - safe ground detected"
    when 1
      puts "  ⚠ Movement restricted - potential cliff detected"  
    when 2
      puts "  ✗ Movement blocked - cliff protection activated"
    end
  else
    puts "  ✓ Movement allowed - not sneaking or very small movement"
  end
  
  puts ""
end

puts "=== Key Features ==="
puts "• Protection threshold: #{Rosegold::Physics::SNEAK_CLIFF_PROTECTION_DISTANCE} blocks (5/8 block)"
puts "• Only active when sneaking"
puts "• Uses existing collision detection system"
puts "• Prevents horizontal movement that would cause falls > threshold"
puts ""
puts "This matches Minecraft's sneak behavior where players are prevented"
puts "from walking off edges when the height difference is significant."