require "../src/rosegold"

# Manually create NBT data and test reading it
puts "🔧 Manual NBT Creation Test"

# Create NBT data manually
buffer = Minecraft::IO::Memory.new

# Write compound tag with "text" field
buffer.write 10_u8      # Compound tag type
buffer.write 0_u16      # Empty name
buffer.write 8_u8       # String tag type
buffer.write 4_u16      # Name length
buffer.print "text"     # Name
buffer.write 5_u16      # String length
buffer.print "Hello"    # String value
buffer.write 0_u8       # End tag

manual_bytes = buffer.to_slice
puts "📦 Manual NBT bytes: #{manual_bytes.hexstring}"

# Try to read it back
begin
  read_io = Minecraft::IO::Memory.new(manual_bytes)
  nbt_tag = Minecraft::NBT::Tag.read(read_io) { |tag_type| puts "Tag type: #{tag_type}" }
  
  puts "✅ Read NBT tag: #{nbt_tag.class}"
  if nbt_tag.is_a?(Minecraft::NBT::CompoundTag)
    puts "Compound contents:"
    nbt_tag.value.each do |key, value|
      puts "  #{key}: #{value}"
    end
    
    # Test direct access
    text_tag = nbt_tag["text"]?
    puts "Direct access to 'text': #{text_tag}"
  end
rescue e
  puts "❌ Failed to read manual NBT: #{e}"
end