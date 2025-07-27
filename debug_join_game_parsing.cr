require "./src/rosegold"

# Read the packet file
packet_bytes = File.read("spec/fixtures/packets/clientbound/join_game_real.bin").to_slice
puts "Packet size: #{packet_bytes.size} bytes"
puts "Full hex: #{packet_bytes.map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"

io = Minecraft::IO::Memory.new(packet_bytes)

# Skip packet ID
packet_id = io.read_byte
puts "Packet ID: 0x#{packet_id.to_s(16).upcase}"

# Let's try to read entity_id as VarInt instead of Int32
puts "Attempting to read entity_id as VarInt:"
entity_id = io.read_var_int
puts "Entity ID (VarInt): #{entity_id}"

puts "Attempting to read hardcore:"
hardcore = io.read_bool
puts "Hardcore: #{hardcore}"

puts "Attempting to read dimension count:"
dim_count = io.read_var_int
puts "Dimension count: #{dim_count}"

puts "Attempting to read dimension names:"
dimension_names = Array(String).new(dim_count) do |i|
  name = io.read_var_string
  puts "  Dimension #{i}: #{name}"
  name
end

puts "Attempting to read max_players:"
max_players = io.read_var_int
puts "Max players: #{max_players}"

puts "Attempting to read view_distance:"
view_distance = io.read_var_int
puts "View distance: #{view_distance}"

puts "Attempting to read simulation_distance:"
simulation_distance = io.read_var_int
puts "Simulation distance: #{simulation_distance}"

puts "Remaining bytes: #{io.size - io.pos}"

# Continue parsing to see what goes wrong
puts "Attempting to read reduced_debug_info:"
reduced_debug_info = io.read_bool
puts "Reduced debug info: #{reduced_debug_info}"

puts "Attempting to read enable_respawn_screen:"
enable_respawn_screen = io.read_bool
puts "Enable respawn screen: #{enable_respawn_screen}"

puts "Attempting to read do_limited_crafting:"
do_limited_crafting = io.read_bool
puts "Do limited crafting: #{do_limited_crafting}"

puts "Attempting to read dimension_type:"
dimension_type = io.read_var_int
puts "Dimension type: #{dimension_type}"

puts "Attempting to read dimension_name:"
dimension_name = io.read_var_string
puts "Dimension name: #{dimension_name}"

puts "Remaining bytes after dimension_name: #{io.size - io.pos}"
if io.size - io.pos > 0
  remaining = Bytes.new(io.size - io.pos)
  io.read(remaining)
  puts "Remaining bytes: #{remaining.map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"
end