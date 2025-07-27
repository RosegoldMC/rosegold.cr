require "file"

# The corrected packet hex from the logs
packet_hex = "2b000011560001136d696e6563726166743a6f766572776f726c64140a0a0001000013" +
             "6d696e6563726166743a6f766572776f726c64c35e74ddb56655b500ff00010000c1ffffff0f00"

# Convert to bytes and save
hex_array = packet_hex.scan(/../).map { |hex| hex[0].to_u8(16) }
packet_bytes = Slice.new(hex_array.size) { |i| hex_array[i] }

File.write("spec/fixtures/packets/clientbound/join_game_int32.bin", packet_bytes)
puts "Saved corrected JoinGame packet (#{packet_bytes.size} bytes) to join_game_int32.bin"
puts "This packet uses Int32 entity_id format as expected by current network protocol"