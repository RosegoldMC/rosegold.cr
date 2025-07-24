require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::LoginAcknowledged do
  describe "protocol support" do
    it "supports protocol 772 (MC 1.21.8)" do
      expect(Rosegold::Serverbound::LoginAcknowledged.supports_protocol?(772_u32)).to be_true
      expect(Rosegold::Serverbound::LoginAcknowledged[772_u32]).to eq(0x03_u8)
    end

    it "does not support protocol 758 (MC 1.18)" do
      expect(Rosegold::Serverbound::LoginAcknowledged.supports_protocol?(758_u32)).to be_false
    end

    it "returns correct supported protocols" do
      supported = Rosegold::Serverbound::LoginAcknowledged.supported_protocols
      expect(supported).to contain(772_u32)
      expect(supported).not_to contain(758_u32)
    end
  end

  describe "packet structure" do
    it "creates a simple packet with no fields" do
      packet = Rosegold::Serverbound::LoginAcknowledged.new
      expect(packet).not_to be_nil
    end

    it "writes only packet ID for protocol 772" do
      # Mock protocol version
      original_protocol = Rosegold::Client.protocol_version
      Rosegold::Client.protocol_version = 772_u32

      packet = Rosegold::Serverbound::LoginAcknowledged.new
      bytes = packet.write

      # Should contain only the packet ID (0x03)
      expect(bytes.size).to eq(1)
      expect(bytes[0]).to eq(0x03_u8)

      # Restore original protocol
      Rosegold::Client.protocol_version = original_protocol
    end
  end

  describe "state information" do
    it "is a LOGIN state packet" do
      expect(Rosegold::Serverbound::LoginAcknowledged.state).to eq(Rosegold::ProtocolState::LOGIN)
    end
  end
end
