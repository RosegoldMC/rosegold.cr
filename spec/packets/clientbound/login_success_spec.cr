require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::LoginSuccess do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/login_success.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  describe "protocol 758 (MC 1.18)" do
    before_each do
      Rosegold::Client.protocol_version = 758_u32
    end

    it "parses the packet" do
      io.read_byte
      packet = Rosegold::Clientbound::LoginSuccess.read(io)

      expect(packet.uuid).to be_a(UUID)
      expect(packet.username).to be_a(String)
      expect(packet.properties).to be_a(Array(Rosegold::Clientbound::LoginSuccess::Property))

      expect(packet.uuid).to eq(UUID.new("23206230-679e-4c49-93c2-9828a0921f2a"))
      expect(packet.username).to eq("Drekamor")
      expect(packet.properties).to be_empty
    end

    it "writes packet the same after parsing" do
      io.read_byte

      expect(Rosegold::Clientbound::LoginSuccess.read(io).write).to eq file_slice
    end
  end

  describe "protocol 767+ (MC 1.21+)" do
    before_each do
      Rosegold::Client.protocol_version = 767_u32
    end

    it "supports protocol-aware packet ID lookup" do
      expect(Rosegold::Clientbound::LoginSuccess[758_u32]).to eq(0x02_u8)
      expect(Rosegold::Clientbound::LoginSuccess[767_u32]).to eq(0x02_u8)
      expect(Rosegold::Clientbound::LoginSuccess[771_u32]).to eq(0x02_u8)
    end

    it "reads packet with properties for MC 1.21+" do
      # Create a mock packet with properties
      test_uuid = UUID.new("12345678-1234-5678-9abc-123456789abc")
      test_username = "TestPlayer"
      test_properties = [
        Rosegold::Clientbound::LoginSuccess::Property.new("textures", "eyJ0aW1lc3RhbXAiOjE1...", "signature123"),
        Rosegold::Clientbound::LoginSuccess::Property.new("locale", "en_US", nil),
      ]

      packet = Rosegold::Clientbound::LoginSuccess.new(test_uuid, test_username, test_properties)
      written_bytes = packet.write

      # Read back the packet
      io = Minecraft::IO::Memory.new(written_bytes)
      io.read_byte # skip packet ID
      parsed_packet = Rosegold::Clientbound::LoginSuccess.read(io)

      expect(parsed_packet.uuid).to eq(test_uuid)
      expect(parsed_packet.username).to eq(test_username)
      expect(parsed_packet.properties.size).to eq(2)
      expect(parsed_packet.properties[0].name).to eq("textures")
      expect(parsed_packet.properties[0].value).to eq("eyJ0aW1lc3RhbXAiOjE1...")
      expect(parsed_packet.properties[0].signature).to eq("signature123")
      expect(parsed_packet.properties[1].name).to eq("locale")
      expect(parsed_packet.properties[1].value).to eq("en_US")
      expect(parsed_packet.properties[1].signature).to be_nil
    end

    it "writes and reads packet with empty properties" do
      test_uuid = UUID.new("12345678-1234-5678-9abc-123456789abc")
      test_username = "TestPlayer"

      packet = Rosegold::Clientbound::LoginSuccess.new(test_uuid, test_username, [] of Rosegold::Clientbound::LoginSuccess::Property)
      written_bytes = packet.write

      # Read back the packet
      io = Minecraft::IO::Memory.new(written_bytes)
      io.read_byte # skip packet ID
      parsed_packet = Rosegold::Clientbound::LoginSuccess.read(io)

      expect(parsed_packet.uuid).to eq(test_uuid)
      expect(parsed_packet.username).to eq(test_username)
      expect(parsed_packet.properties).to be_empty
    end
  end

  describe "protocol support" do
    it "supports protocol 772 only" do
      expect(Rosegold::Clientbound::LoginSuccess.supports_protocol?(772_u32)).to be_true
      expect(Rosegold::Clientbound::LoginSuccess.supports_protocol?(999_u32)).to be_false
    end

    it "returns correct supported protocols" do
      protocols = Rosegold::Clientbound::LoginSuccess.supported_protocols
      expect(protocols).to contain(772_u32)
    end
  end
end
