require "./src/rosegold"

# Parse the failing packet from the log
packet_hex = "2b000011560001136d696e6563726166743a6f766572776f726c64140a0a0001000013" +
             "6d696e6563726166743a6f766572776f726c64c35e74ddb56655b500ff00010000c1ffffff0f00"

# Convert hex string to bytes
hex_array = packet_hex.scan(/../).map { |hex| hex[0].to_u8(16) }
packet_bytes = Slice.new(hex_array.size) { |i| hex_array[i] }

puts "Packet size: #{packet_bytes.size} bytes"
puts "Packet hex: #{packet_bytes.map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

io = Minecraft::IO::Memory.new(packet_bytes)

# Skip packet ID
packet_id = io.read_byte
puts "Packet ID: 0x#{packet_id.to_s(16).upcase}"

# Parse step by step
puts "Byte by byte analysis:"
puts "Remaining: #{io.size - io.pos} bytes"

# Try to read entity_id as different types
puts "\nTrying different entity_id interpretations:"

# Reset and try entity_id as Int32 (old way)
io.pos = 1  # Reset after packet ID
begin
  entity_id_int32 = io.read_int
  puts "Entity ID as Int32: #{entity_id_int32} (0x#{entity_id_int32.to_s(16)})"
  puts "Next 4 bytes after Int32: #{(io.pos...io.pos+4).map { |i| "0x#{packet_bytes[i].to_s(16).upcase}" }.join(" ")}"
rescue ex
  puts "Failed to read as Int32: #{ex.message}"
end

# Reset and try the correct way with Int32 entity_id
io.pos = 1  # Reset after packet ID
begin
  entity_id_int32 = io.read_int
  puts "Entity ID as Int32: #{entity_id_int32}"
  puts "Position after Int32: #{io.pos}, remaining: #{io.size - io.pos}"
  
  # Continue parsing
  hardcore = io.read_bool
  puts "Hardcore: #{hardcore}"
  
  dim_count = io.read_var_int
  puts "Dim count: #{dim_count}"
  puts "Remaining bytes: #{io.size - io.pos}"
  
  # Parse dimensions
  (0...dim_count).each do |i|
    puts "Reading dimension #{i}, #{io.size - io.pos} bytes remaining"
    if io.size - io.pos > 0
      name_len = io.read_var_int
      puts "  Dimension #{i} name length: #{name_len}"
      if io.size - io.pos >= name_len
        name_bytes = Bytes.new(name_len)
        io.read(name_bytes)
        name = String.new(name_bytes)
        puts "  Dimension #{i}: #{name}"
      else
        puts "  Not enough bytes for dimension name"
        break
      end
    else
      puts "  No bytes remaining for dimension #{i}"
      break
    end
  end
  
rescue ex
  puts "Failed during parsing: #{ex.message}"
end