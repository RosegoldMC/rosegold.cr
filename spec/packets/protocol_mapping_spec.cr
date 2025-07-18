require "../spec_helper"

Spectator.describe Rosegold::Packets::ProtocolMapping do
  describe "packet ID mapping system" do
    # Create a test packet class to verify the macro works
    class TestPacket < Rosegold::Serverbound::Packet
      include Rosegold::Packets::ProtocolMapping

      packet_ids({
        758_u32 => 0x10_u8, # MC 1.18
        767_u32 => 0x15_u8, # MC 1.21
        771_u32 => 0x15_u8, # MC 1.21.6
      })

      def write : Bytes
        Minecraft::IO::Memory.new.tap do |buffer|
          buffer.write self.class.packet_id_for_protocol(771_u32)
        end.to_slice
      end
    end

    it "provides protocol-specific packet IDs via [] syntax" do
      expect(TestPacket[758_u32]).to eq(0x10_u8)
      expect(TestPacket[767_u32]).to eq(0x15_u8)
      expect(TestPacket[771_u32]).to eq(0x15_u8)
    end

    it "falls back to default packet ID for unknown protocols" do
      # Should return the first defined packet ID as default
      expect(TestPacket[999_u32]).to eq(0x10_u8)
    end

    it "provides backward compatible packet_id class getter" do
      # Should use the first protocol's packet ID for registration compatibility
      expect(TestPacket.packet_id).to eq(0x10_u8)
    end

    it "provides packet_id_for_protocol method" do
      expect(TestPacket.packet_id_for_protocol(758_u32)).to eq(0x10_u8)
      expect(TestPacket.packet_id_for_protocol(767_u32)).to eq(0x15_u8)
      expect(TestPacket.packet_id_for_protocol(771_u32)).to eq(0x15_u8)
    end

    it "provides default_packet_id method" do
      expect(TestPacket.default_packet_id).to eq(0x10_u8)
    end

    it "provides supported_protocols method" do
      protocols = TestPacket.supported_protocols
      expect(protocols).to contain(758_u32)
      expect(protocols).to contain(767_u32)
      expect(protocols).to contain(771_u32)
    end

    it "checks protocol support via supports_protocol?" do
      expect(TestPacket.supports_protocol?(758_u32)).to be_true
      expect(TestPacket.supports_protocol?(767_u32)).to be_true
      expect(TestPacket.supports_protocol?(771_u32)).to be_true
      expect(TestPacket.supports_protocol?(999_u32)).to be_false
    end
  end
end

Spectator.describe Rosegold::Serverbound::LoginStart do
  describe "protocol-aware packet ID system" do
    it "uses correct packet IDs for different protocol versions" do
      expect(Rosegold::Serverbound::LoginStart[758_u32]).to eq(0x00_u8)
      expect(Rosegold::Serverbound::LoginStart[767_u32]).to eq(0x00_u8)
      expect(Rosegold::Serverbound::LoginStart[771_u32]).to eq(0x00_u8)
    end

    it "supports all required protocols" do
      expect(Rosegold::Serverbound::LoginStart.supports_protocol?(758_u32)).to be_true
      expect(Rosegold::Serverbound::LoginStart.supports_protocol?(767_u32)).to be_true
      expect(Rosegold::Serverbound::LoginStart.supports_protocol?(771_u32)).to be_true
    end

    it "writes correct packet ID based on protocol version" do
      login_start_758 = Rosegold::Serverbound::LoginStart.new("TestUser", nil, 758_u32)
      login_start_767 = Rosegold::Serverbound::LoginStart.new("TestUser", UUID.random, 767_u32)

      # Both should use packet ID 0x00 but write different formats
      bytes_758 = login_start_758.write
      bytes_767 = login_start_767.write

      expect(bytes_758[0]).to eq(0x00_u8)
      expect(bytes_767[0]).to eq(0x00_u8)

      # Protocol 767+ should have more bytes due to UUID
      expect(bytes_767.size).to be > bytes_758.size
    end
  end
end

Spectator.describe Rosegold::Serverbound::KeepAlive do
  describe "protocol-aware packet ID system" do
    it "uses different packet IDs for different protocol versions" do
      expect(Rosegold::Serverbound::KeepAlive[758_u32]).to eq(0x0F_u8) # MC 1.18
      expect(Rosegold::Serverbound::KeepAlive[767_u32]).to eq(0x12_u8) # MC 1.21 - CHANGED!
      expect(Rosegold::Serverbound::KeepAlive[771_u32]).to eq(0x12_u8) # MC 1.21.6
    end

    it "writes correct packet ID in bytes" do
      # Mock different protocol versions
      keep_alive_758 = Rosegold::Serverbound::KeepAlive.new(12345_i64)
      keep_alive_767 = Rosegold::Serverbound::KeepAlive.new(12345_i64)

      # Test with different protocol versions
      original_version = Rosegold::Client.protocol_version

      begin
        Rosegold::Client.protocol_version = 758_u32
        bytes_758 = keep_alive_758.write
        expect(bytes_758[0]).to eq(0x0F_u8)

        Rosegold::Client.protocol_version = 767_u32
        bytes_767 = keep_alive_767.write
        expect(bytes_767[0]).to eq(0x12_u8)
      ensure
        Rosegold::Client.protocol_version = original_version
      end
    end
  end
end

Spectator.describe Rosegold::Serverbound::PlayerPosition do
  describe "protocol-aware packet ID system" do
    it "uses different packet IDs for different protocol versions" do
      expect(Rosegold::Serverbound::PlayerPosition[758_u32]).to eq(0x11_u8) # MC 1.18
      expect(Rosegold::Serverbound::PlayerPosition[767_u32]).to eq(0x14_u8) # MC 1.21 - CHANGED!
      expect(Rosegold::Serverbound::PlayerPosition[771_u32]).to eq(0x14_u8) # MC 1.21.6
    end

    it "writes correct packet ID in bytes" do
      # Mock different protocol versions
      pos_758 = Rosegold::Serverbound::PlayerPosition.new(100.0, 64.0, 100.0, true)
      pos_767 = Rosegold::Serverbound::PlayerPosition.new(100.0, 64.0, 100.0, true)

      # Test with different protocol versions
      original_version = Rosegold::Client.protocol_version

      begin
        Rosegold::Client.protocol_version = 758_u32
        bytes_758 = pos_758.write
        expect(bytes_758[0]).to eq(0x11_u8)

        Rosegold::Client.protocol_version = 767_u32
        bytes_767 = pos_767.write
        expect(bytes_767[0]).to eq(0x14_u8)
      ensure
        Rosegold::Client.protocol_version = original_version
      end
    end
  end
end

Spectator.describe Rosegold::Serverbound::Handshake do
  describe "protocol-aware packet ID system" do
    it "uses same packet ID across all protocol versions" do
      expect(Rosegold::Serverbound::Handshake[758_u32]).to eq(0x00_u8)
      expect(Rosegold::Serverbound::Handshake[767_u32]).to eq(0x00_u8)
      expect(Rosegold::Serverbound::Handshake[771_u32]).to eq(0x00_u8)
    end

    it "writes correct packet ID in bytes" do
      handshake = Rosegold::Serverbound::Handshake.new(767_u32, "localhost", 25565, 2)
      bytes = handshake.write
      expect(bytes[0]).to eq(0x00_u8)
    end
  end
end
