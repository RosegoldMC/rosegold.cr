require "../src/rosegold"

# Test NBT encoding/decoding for chat messages
puts "🧪 Testing Chat Message NBT Encoding/Decoding"

# Create a test chat message
test_message = "§6Hello §aWorld!"
chat = Rosegold::Chat.new(test_message)
chat_packet = Rosegold::Clientbound::ChatMessage.new(chat, false)

puts "📝 Original message: #{test_message}"

# Encode the packet to bytes
encoded_bytes = chat_packet.write
puts "📦 Encoded packet size: #{encoded_bytes.size} bytes"
puts "🔍 Encoded bytes (hex): #{encoded_bytes.hexstring}"

# Try to decode it back
begin
  io = Minecraft::IO::Memory.new(encoded_bytes[1..])  # Skip packet ID
  
  # Debug: manually read the NBT to see what we get
  nbt_tag = Minecraft::NBT::Tag.read(io) { |tag_type| puts "🔍 NBT tag type: #{tag_type}" }
  puts "🔍 NBT tag class: #{nbt_tag.class}"
  if nbt_tag.is_a?(Minecraft::NBT::CompoundTag)
    puts "🔍 Compound tag contents:"
    nbt_tag.value.each do |key, value|
      puts "   #{key}: #{value.class} = #{value}"
    end
  end
  
  # Reset and decode normally
  io = Minecraft::IO::Memory.new(encoded_bytes[1..])  # Skip packet ID
  decoded_packet = Rosegold::Clientbound::ChatMessage.read(io)
  
  puts "✅ Successfully decoded packet!"
  puts "📄 Decoded message: #{decoded_packet.message}"
  puts "🎯 Overlay flag: #{decoded_packet.overlay}"
  
  if decoded_packet.message.to_s == test_message
    puts "🎉 Roundtrip test PASSED - messages match!"
  else
    puts "❌ Roundtrip test FAILED - messages don't match"
    puts "   Expected: #{test_message}"  
    puts "   Got: #{decoded_packet.message.to_s}"
  end
  
rescue e
  puts "❌ Failed to decode packet: #{e}"
  puts "   This indicates an NBT encoding issue"
end