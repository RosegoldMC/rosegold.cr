require "./src/rosegold"

Log.setup("debug")

# Add packet capture logic
module Rosegold::Packets::Connection
  def self.decode_clientbound_packet(
    packet_bytes : Bytes,
    protocol_state : ProtocolState,
    protocol_version : UInt32,
  ) : Clientbound::Packet
    Minecraft::IO::Memory.new(packet_bytes).try do |pkt_io|
      pkt_id = pkt_io.read_byte || raise "Empty packet"

      # Capture JoinGame packets
      if pkt_id == 0x2B_u8 && protocol_state == ProtocolState::Play
        puts "Capturing fresh JoinGame packet!"
        puts "Packet size: #{packet_bytes.size} bytes"
        puts "Packet hex: #{packet_bytes.map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}"
        
        # Save to file
        File.write("spec/fixtures/packets/clientbound/join_game_fresh.bin", packet_bytes)
        puts "Saved to join_game_fresh.bin"
      end

      pkt_type = protocol_state.get_clientbound_packet(pkt_id, protocol_version)

      unless pkt_type && pkt_type.responds_to? :read
        return Clientbound::RawPacket.new(packet_bytes)
      end

      begin
        pkt_type.read pkt_io
      rescue ex
        # Log detailed error information for packet parsing failures
        packet_name = pkt_type.name
        packet_hex = "0x#{pkt_id.to_s(16).upcase.rjust(2, '0')}"

        Log.warn { "Failed to parse clientbound packet #{packet_name} (#{packet_hex}) in #{protocol_state.name} state for protocol #{protocol_version}: #{ex.message}" }
        
        # If it's a JoinGame packet, save the failing packet for analysis
        if pkt_id == 0x2B_u8
          puts "Saving failing JoinGame packet for analysis"
          File.write("spec/fixtures/packets/clientbound/join_game_failing.bin", packet_bytes)
        end
        
        raise ex
      end
    end || raise "Packet parsing failed"  
  end
end

# Now try to connect to get a fresh packet
puts "This utility will capture fresh JoinGame packets. Connect to a server to trigger capture."
puts "Make sure to connect to a Minecraft 1.21.8 server."