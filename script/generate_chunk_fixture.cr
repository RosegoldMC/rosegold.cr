#!/usr/bin/env crystal

# Script to generate chunk data fixture for different protocol versions
# Based on the suggestion from @grepsedawk to capture actual packet data
# Usage: Include this code in the client's read_packet method temporarily

def capture_chunk_packet(packet, raw_packet)
  if packet.is_a?(Rosegold::Clientbound::ChunkData)
    protocol_version = Rosegold::Client.protocol_version
    filename = "chunk_data_#{protocol_version}.mcpacket"
    filepath = File.join(__DIR__, "../spec/fixtures/packets/clientbound/#{filename}")
    
    File.write(filepath, raw_packet)
    puts "Captured chunk data packet for protocol #{protocol_version} to #{filename}"
    puts "Chunk coordinates: #{packet.chunk_x}, #{packet.chunk_z}"
    puts "Data size: #{packet.data.size} bytes"
    puts "Block entities count: #{packet.block_entities.size}"
  end
end

# To use this, temporarily add this code to Client#read_packet:
# ```
# private def read_packet
#   raise NotConnected.new unless connected?
#   raw_packet = connection.read_raw_packet
# 
#   emit_event Event::RawPacket.new raw_packet
# 
#   packet = Connection::Client.decode_packet raw_packet, connection.state
#   Log.trace { "RECV 0x#{raw_packet[0].to_s 16} #{packet}" }
# 
#   # Capture chunk data packets for fixture generation
#   if packet.is_a?(Rosegold::Clientbound::ChunkData)
#     File.write File.join(__DIR__, "../../spec/fixtures/packets/clientbound/chunk_data_#{Rosegold::Client.protocol_version}.mcpacket"), raw_packet
#   end
# 
#   packet.callback(self)
# 
#   emit_event packet
# 
#   packet
# end
# ```