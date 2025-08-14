require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::PluginMessage do
  describe "protocol support" do
    it "supports protocol 772 (MC 1.21.8)" do
      expect(Rosegold::Serverbound::PluginMessage.supports_protocol?(772_u32)).to be_true
      expect(Rosegold::Serverbound::PluginMessage[772_u32]).to eq(0x17_u8)
    end

    it "returns correct supported protocols" do
      supported = Rosegold::Serverbound::PluginMessage.supported_protocols
      expect(supported).to contain(772_u32)
    end
  end

  describe "packet construction" do
    it "creates a packet with channel and data" do
      data = "test_data".to_slice
      packet = Rosegold::Serverbound::PluginMessage.new("test:channel", data)

      expect(packet.channel).to eq("test:channel")
      expect(packet.data).to eq(data)
    end

    it "creates a packet with string convenience constructor" do
      packet = Rosegold::Serverbound::PluginMessage.new("test:channel", "test_data")

      expect(packet.channel).to eq("test:channel")
      expect(packet.data).to eq("test_data".to_slice)
    end

    it "creates minecraft:brand packet with convenience method" do
      packet = Rosegold::Serverbound::PluginMessage.brand("Rosegold")

      expect(packet.channel).to eq("minecraft:brand")
      expect(packet.data).to eq("Rosegold".to_slice)
    end
  end

  describe "packet serialization" do
    it "writes correct packet data for protocol 772" do
      # Mock protocol version
      original_protocol = Rosegold::Client.protocol_version
      Rosegold::Client.protocol_version = 772_u32

      packet = Rosegold::Serverbound::PluginMessage.brand("Rosegold")
      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read and verify packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x17_u8)

      # Read and verify channel
      channel = io.read_var_string
      expect(channel).to eq("minecraft:brand")

      # Read remaining data
      remaining_bytes = Bytes.new(bytes.size - io.pos)
      io.read_fully(remaining_bytes)
      data_string = String.new(remaining_bytes)
      expect(data_string).to eq("Rosegold")

      # Restore original protocol
      Rosegold::Client.protocol_version = original_protocol
    end

    it "writes correct packet structure for custom channel" do
      # Mock protocol version
      original_protocol = Rosegold::Client.protocol_version
      Rosegold::Client.protocol_version = 772_u32

      packet = Rosegold::Serverbound::PluginMessage.new("custom:test", "hello")
      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read and verify packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x17_u8)

      # Read and verify channel
      channel = io.read_var_string
      expect(channel).to eq("custom:test")

      # Read remaining data
      remaining_bytes = Bytes.new(bytes.size - io.pos)
      io.read_fully(remaining_bytes)
      data_string = String.new(remaining_bytes)
      expect(data_string).to eq("hello")

      # Restore original protocol
      Rosegold::Client.protocol_version = original_protocol
    end
  end
end
