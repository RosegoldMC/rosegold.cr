require "./src/rosegold"

puts "🧪 Testing JoinGame packet roundtrip..."

# Set protocol version
Rosegold::Client.protocol_version = 772_u32

# Read the captured real packet
packet_bytes = File.read("spec/fixtures/packets/clientbound/join_game_real.bin").to_slice
puts "Original packet size: #{packet_bytes.size} bytes"
puts "Original bytes: #{packet_bytes[0, [32, packet_bytes.size].min].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

# Parse the packet
io = Minecraft::IO::Memory.new(packet_bytes[1..]) # Skip packet ID (0x2B)
join_game = Rosegold::Clientbound::JoinGame.read(io)

puts "\nParsed packet:"
puts "  Entity ID: #{join_game.entity_id}"
puts "  Hardcore: #{join_game.hardcore?}"
puts "  Dimensions: #{join_game.dimension_names}"
puts "  Max players: #{join_game.max_players}"
puts "  View distance: #{join_game.view_distance}"
puts "  Dimension type: #{join_game.dimension_type}"
puts "  Dimension name: #{join_game.dimension_name}"
puts "  Gamemode: #{join_game.gamemode}"

# Re-serialize the packet
rewritten_bytes = join_game.write
puts "\nRewritten packet size: #{rewritten_bytes.size} bytes"
puts "Rewritten bytes: #{rewritten_bytes[0, [32, rewritten_bytes.size].min].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

# Compare
if packet_bytes == rewritten_bytes
  puts "\n✅ Perfect match! Packet roundtrip successful."
else
  puts "\n❌ Mismatch detected!"
  puts "Original:  #{packet_bytes.size} bytes"
  puts "Rewritten: #{rewritten_bytes.size} bytes"
  
  # Show differences byte by byte
  min_size = [packet_bytes.size, rewritten_bytes.size].min
  max_size = [packet_bytes.size, rewritten_bytes.size].max
  
  puts "\nByte-by-byte comparison:"
  (0...min_size).each do |i|
    orig = packet_bytes[i]
    rewr = rewritten_bytes[i]
    if orig != rewr
      puts "  #{i.to_s.rjust(3)}: original=0x#{orig.to_s(16).upcase.rjust(2, '0')} rewritten=0x#{rewr.to_s(16).upcase.rjust(2, '0')} ❌"
    else
      puts "  #{i.to_s.rjust(3)}: 0x#{orig.to_s(16).upcase.rjust(2, '0')} ✅"
    end
  end
  
  # Show extra bytes if any
  if packet_bytes.size != rewritten_bytes.size
    puts "\nSize difference:"
    if packet_bytes.size > rewritten_bytes.size
      puts "Original has #{packet_bytes.size - rewritten_bytes.size} extra bytes: #{packet_bytes[min_size..].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"
    else
      puts "Rewritten has #{rewritten_bytes.size - packet_bytes.size} extra bytes: #{rewritten_bytes[min_size..].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"
    end
  end
  
  exit 1
end