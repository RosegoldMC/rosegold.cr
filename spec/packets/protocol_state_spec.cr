require "spectator"
require "../../src/rosegold"

Spectator.describe "Protocol-aware ProtocolState system" do
  describe "ProtocolState registration and lookup" do
    it "registers packets for multiple protocols automatically" do
      # Test that the KeepAlive packet is registered for multiple protocols
      play_state = Rosegold::ProtocolState::PLAY

      # Check clientbound KeepAlive registration for different protocols
      keepalive_758 = play_state.get_clientbound_packet(0x12_u8, 758_u32) # MC 1.18
      keepalive_767 = play_state.get_clientbound_packet(0x04_u8, 767_u32) # MC 1.21
      keepalive_771 = play_state.get_clientbound_packet(0x04_u8, 771_u32) # MC 1.21.6

      expect(keepalive_758).to eq(Rosegold::Clientbound::KeepAlive)
      expect(keepalive_767).to eq(Rosegold::Clientbound::KeepAlive)
      expect(keepalive_771).to eq(Rosegold::Clientbound::KeepAlive)

      # Check serverbound KeepAlive registration for different protocols
      keepalive_sb_758 = play_state.get_serverbound_packet(0x0F_u8, 758_u32) # MC 1.18
      keepalive_sb_767 = play_state.get_serverbound_packet(0x1B_u8, 767_u32) # MC 1.21
      keepalive_sb_771 = play_state.get_serverbound_packet(0x1B_u8, 771_u32) # MC 1.21.6

      expect(keepalive_sb_758).to eq(Rosegold::Serverbound::KeepAlive)
      expect(keepalive_sb_767).to eq(Rosegold::Serverbound::KeepAlive)
      expect(keepalive_sb_771).to eq(Rosegold::Serverbound::KeepAlive)
    end

    it "returns nil for unknown packet ID and protocol combinations" do
      play_state = Rosegold::ProtocolState::PLAY

      # Test with non-existent packet IDs
      expect(play_state.get_clientbound_packet(0xFF_u8, 758_u32)).to be_nil
      expect(play_state.get_serverbound_packet(0xFF_u8, 767_u32)).to be_nil

      # Test with known packet ID but unsupported protocol
      expect(play_state.get_clientbound_packet(0x12_u8, 999_u32)).to be_nil
    end

    it "provides legacy compatibility methods" do
      play_state = Rosegold::ProtocolState::PLAY

      # Test legacy compatibility for protocol 758
      legacy_cb_758 = play_state.clientbound_for_protocol(758_u32)
      legacy_sb_758 = play_state.serverbound_for_protocol(758_u32)

      expect(legacy_cb_758).to be_a(Hash(UInt8, Rosegold::Clientbound::Packet.class))
      expect(legacy_sb_758).to be_a(Hash(UInt8, Rosegold::Serverbound::Packet.class))

      # Should contain the KeepAlive packet at the correct ID for protocol 758
      expect(legacy_cb_758[0x12_u8]?).to eq(Rosegold::Clientbound::KeepAlive)
      expect(legacy_sb_758[0x0F_u8]?).to eq(Rosegold::Serverbound::KeepAlive)

      # Test legacy compatibility for protocol 767
      legacy_cb_767 = play_state.clientbound_for_protocol(767_u32)
      legacy_sb_767 = play_state.serverbound_for_protocol(767_u32)

      # Should contain the KeepAlive packet at the correct ID for protocol 767
      expect(legacy_cb_767[0x04_u8]?).to eq(Rosegold::Clientbound::KeepAlive)
      expect(legacy_sb_767[0x1B_u8]?).to eq(Rosegold::Serverbound::KeepAlive)
    end

    it "handles packets that don't use the protocol-aware system" do
      # Test with a packet that might not use packet_ids macro (fallback)
      # Since we want all packets to use the system, this tests backward compatibility
      play_state = Rosegold::ProtocolState::PLAY

      # The system should still register packets, even if they fall back to default protocol
      clientbound_count = play_state.clientbound.size
      serverbound_count = play_state.serverbound.size

      expect(clientbound_count).to be > 0
      expect(serverbound_count).to be > 0
    end
  end

  describe "protocol-aware packet decoding" do
    it "can decode packets using protocol version" do
      # Create a mock packet with KeepAlive data
      # For MC 1.18 (protocol 758), KeepAlive clientbound is 0x12
      # For MC 1.21 (protocol 767), KeepAlive clientbound is 0x04

      # Create packet bytes for KeepAlive with ID 0x12 (MC 1.18)
      packet_bytes_758 = Bytes[0x12_u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01] # ID + 8-byte long

      # Create packet bytes for KeepAlive with ID 0x04 (MC 1.21)
      packet_bytes_767 = Bytes[0x04_u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01] # ID + 8-byte long

      # Test protocol-aware decoding
      decoded_758 = Rosegold::Connection::Client.decode_clientbound_packet(
        packet_bytes_758,
        Rosegold::ProtocolState::PLAY,
        758_u32
      )

      decoded_767 = Rosegold::Connection::Client.decode_clientbound_packet(
        packet_bytes_767,
        Rosegold::ProtocolState::PLAY,
        767_u32
      )

      # Both should decode to KeepAlive packets
      expect(decoded_758).to be_a(Rosegold::Clientbound::KeepAlive)
      expect(decoded_767).to be_a(Rosegold::Clientbound::KeepAlive)

      # Check that the keep_alive_id is correctly parsed
      if decoded_758.is_a?(Rosegold::Clientbound::KeepAlive)
        expect(decoded_758.keep_alive_id).to eq(1_i64)
      end

      if decoded_767.is_a?(Rosegold::Clientbound::KeepAlive)
        expect(decoded_767.keep_alive_id).to eq(1_i64)
      end
    end

    it "falls back to RawPacket for unknown packet IDs" do
      # Create packet bytes with unknown packet ID
      unknown_packet_bytes = Bytes[0xFF_u8, 0x01, 0x02, 0x03]

      # Should decode to RawPacket since 0xFF is not a known packet ID
      decoded = Rosegold::Connection::Client.decode_clientbound_packet(
        unknown_packet_bytes,
        Rosegold::ProtocolState::PLAY,
        758_u32
      )

      expect(decoded).to be_a(Rosegold::Clientbound::RawPacket)
      if decoded.is_a?(Rosegold::Clientbound::RawPacket)
        expect(decoded.bytes).to eq(unknown_packet_bytes)
      end
    end
  end
end
