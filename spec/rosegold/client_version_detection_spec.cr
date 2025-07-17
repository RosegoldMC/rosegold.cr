require "../spec_helper"

# Mock for testing status responses
class MockStatusResponse
  getter json_response : JSON::Any

  def initialize(@json_response : JSON::Any); end
end

# Test client that allows overriding the status method
class TestableClient < Rosegold::Client
  property status_response : MockStatusResponse?
  property should_raise_error : Bool = false

  def status
    if should_raise_error
      raise IO::Error.new("Connection failed")
    end

    if response = status_response
      response
    else
      super
    end
  end

  # Make private method public for testing
  def test_detect_and_set_protocol_version
    detect_and_set_protocol_version
  end
end

Spectator.describe "Rosegold::Client version detection" do
  describe "#detect_and_set_protocol_version" do
    it "detects MC 1.21.6 protocol version (771) from server status" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Set up mock response for 1.21.6 server
      client.status_response = MockStatusResponse.new(JSON.parse(%({"version": {"protocol": 771}})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to eq(771_u32)
      expect(client.protocol_version).to eq(771_u32)
    end

    it "detects MC 1.21 protocol version (767) from server status" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Set up mock response for 1.21 server
      client.status_response = MockStatusResponse.new(JSON.parse(%({"version": {"protocol": 767}})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to eq(767_u32)
      expect(client.protocol_version).to eq(767_u32)
    end

    it "detects MC 1.18 protocol version (758) from server status" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Set up mock response for 1.18 server
      client.status_response = MockStatusResponse.new(JSON.parse(%({"version": {"protocol": 758}})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to eq(758_u32)
      expect(client.protocol_version).to eq(758_u32)
    end

    it "falls back to default protocol version when status parsing fails" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      original_default = Rosegold::Client.protocol_version

      # Set up mock response with malformed data
      client.status_response = MockStatusResponse.new(JSON.parse(%({"invalid": "response"})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to be_nil
      expect(client.protocol_version).to eq(original_default)
    end

    it "falls back to default protocol version when status call raises exception" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      original_default = Rosegold::Client.protocol_version

      # Set up mock to raise exception
      client.should_raise_error = true

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to be_nil
      expect(client.protocol_version).to eq(original_default)
    end

    it "handles missing protocol field in version object" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      original_default = Rosegold::Client.protocol_version

      # Set up mock response without protocol field
      client.status_response = MockStatusResponse.new(JSON.parse(%({"version": {"name": "1.21"}})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to be_nil
      expect(client.protocol_version).to eq(original_default)
    end

    it "handles missing version object entirely" do
      client = TestableClient.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      original_default = Rosegold::Client.protocol_version

      # Set up mock response without version object
      client.status_response = MockStatusResponse.new(JSON.parse(%({"description": {"text": "A Minecraft Server"}})))

      # Call the method
      client.test_detect_and_set_protocol_version

      expect(client.detected_protocol_version).to be_nil
      expect(client.protocol_version).to eq(original_default)
    end
  end

  describe "#protocol_version" do
    it "returns detected protocol version when available" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      client.detected_protocol_version = 758_u32

      expect(client.protocol_version).to eq(758_u32)
    end

    it "returns class default when no detected version" do
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})
      original_default = Rosegold::Client.protocol_version

      expect(client.detected_protocol_version).to be_nil
      expect(client.protocol_version).to eq(original_default)
    end
  end

  describe "LoginStart packet format adaptation" do
    it "includes UUID for protocol 771+ (MC 1.21.6)" do
      uuid = UUID.new("550e8400-e29b-41d4-a716-446655440000")
      packet = Rosegold::Serverbound::LoginStart.new("testuser", uuid, 771_u32)

      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x00_u8)

      # Read username
      username = io.read_var_string
      expect(username).to eq("testuser")

      # Should include UUID for protocol 771
      uuid_from_packet = io.read_uuid
      expect(uuid_from_packet).to eq(uuid)
    end

    it "includes UUID for protocol 767+ (MC 1.21)" do
      uuid = UUID.new("550e8400-e29b-41d4-a716-446655440000")
      packet = Rosegold::Serverbound::LoginStart.new("testuser", uuid, 767_u32)

      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x00_u8)

      # Read username
      username = io.read_var_string
      expect(username).to eq("testuser")

      # Should include UUID for protocol 767
      uuid_from_packet = io.read_uuid
      expect(uuid_from_packet).to eq(uuid)
    end

    it "excludes UUID for protocol 758 (MC 1.18)" do
      packet = Rosegold::Serverbound::LoginStart.new("testuser", nil, 758_u32)

      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read packet ID
      packet_id = io.read_byte
      expect(packet_id).to eq(0x00_u8)

      # Read username
      username = io.read_var_string
      expect(username).to eq("testuser")

      # Should not have any more data for protocol 758
      expect(io.pos).to eq(bytes.size)
    end

    it "uses default UUID when none provided for protocol 767+" do
      packet = Rosegold::Serverbound::LoginStart.new("testuser", nil, 767_u32)

      bytes = packet.write
      io = Minecraft::IO::Memory.new(bytes)

      # Read packet ID and username
      io.read_byte
      io.read_var_string

      # Should include default UUID for protocol 767
      uuid_from_packet = io.read_uuid
      expect(uuid_from_packet).to eq(UUID.new("00000000-0000-0000-0000-000000000000"))
    end
  end

  describe "Instance-specific protocol detection" do
    it "allows different clients to have different detected protocol versions" do
      client1 = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser1"})
      client2 = Rosegold::Client.new("localhost", 25566, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser2"})

      # Set different detected versions
      client1.detected_protocol_version = 758_u32
      client2.detected_protocol_version = 767_u32

      expect(client1.protocol_version).to eq(758_u32)
      expect(client2.protocol_version).to eq(767_u32)

      # Should not affect each other
      expect(client1.protocol_version).not_to eq(client2.protocol_version)
    end

    it "does not affect global class protocol version" do
      original_class_version = Rosegold::Client.protocol_version
      client = Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "testuser"})

      # Set instance-specific detected version
      client.detected_protocol_version = 758_u32

      # Class version should remain unchanged
      expect(Rosegold::Client.protocol_version).to eq(original_class_version)
      expect(client.protocol_version).to eq(758_u32)
    end
  end
end
