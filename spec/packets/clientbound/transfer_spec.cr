require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::Transfer do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::Transfer[772_u32]).to eq(0x0B_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::Transfer.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::Transfer.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Clientbound::Transfer.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is properly registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_clientbound_packet(0x0B_u8, 772_u32)).to eq(Rosegold::Clientbound::Transfer)
  end

  describe "packet parsing" do
    it "correctly parses host and port from packet data" do
      # Create a mock packet with test data
      io = Minecraft::IO::Memory.new
      io.write "example.server.com" # Host as var string
      io.write 25565_u32            # Port as var int

      # Reset position to read
      io.pos = 0

      packet = Rosegold::Clientbound::Transfer.read(io)

      expect(packet.host).to eq("example.server.com")
      expect(packet.port).to eq(25565_u32)
    end

    it "handles different host formats" do
      test_cases = [
        {"localhost", 25565_u32},
        {"127.0.0.1", 8080_u32},
        {"play.hypixel.net", 25565_u32},
        {"mc.server.example.com", 19132_u32},
      ]

      test_cases.each do |host, port|
        io = Minecraft::IO::Memory.new
        io.write host
        io.write port
        io.pos = 0

        packet = Rosegold::Clientbound::Transfer.read(io)

        expect(packet.host).to eq(host)
        expect(packet.port).to eq(port)
      end
    end

    it "handles maximum string length host" do
      # Test with very long hostname (approaching the 32767 limit mentioned in protocol)
      long_host = "a" * 100 + ".example.com"

      io = Minecraft::IO::Memory.new
      io.write long_host
      io.write 25565_u32
      io.pos = 0

      packet = Rosegold::Clientbound::Transfer.read(io)

      expect(packet.host).to eq(long_host)
      expect(packet.port).to eq(25565_u32)
    end
  end

  describe "round-trip serialization" do
    it "can write and read transfer packet data" do
      original_packet = Rosegold::Clientbound::Transfer.new("roundtrip.test.com", 54321_u32)

      # Write the packet
      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)

      # Read back (skip packet ID)
      io.read_byte
      read_packet = Rosegold::Clientbound::Transfer.read(io)

      expect(read_packet.host).to eq(original_packet.host)
      expect(read_packet.port).to eq(original_packet.port)
    end
  end

  describe "callback behavior" do
    it "logs transfer request when callback is invoked" do
      packet = Rosegold::Clientbound::Transfer.new("callback.test.com", 9999_u32)
      mock_client = client

      # The callback should not raise an error
      expect { packet.callback(mock_client) }.not_to raise_error
    end

    it "handles various host and port combinations in callback" do
      test_cases = [
        {"localhost", 25565_u32},
        {"192.168.1.100", 25566_u32},
        {"production.server.net", 443_u32},
      ]

      test_cases.each do |host, port|
        packet = Rosegold::Clientbound::Transfer.new(host, port)
        mock_client = client

        expect { packet.callback(mock_client) }.not_to raise_error
      end
    end
  end

  describe "edge cases" do
    it "handles empty host string" do
      io = Minecraft::IO::Memory.new
      io.write ""
      io.write 25565_u32
      io.pos = 0

      packet = Rosegold::Clientbound::Transfer.read(io)

      expect(packet.host).to eq("")
      expect(packet.port).to eq(25565_u32)
    end

    it "handles port 0" do
      io = Minecraft::IO::Memory.new
      io.write "test.com"
      io.write 0_u32
      io.pos = 0

      packet = Rosegold::Clientbound::Transfer.read(io)

      expect(packet.host).to eq("test.com")
      expect(packet.port).to eq(0_u32)
    end

    it "handles maximum port number" do
      max_port = 65535_u32

      io = Minecraft::IO::Memory.new
      io.write "maxport.test.com"
      io.write max_port
      io.pos = 0

      packet = Rosegold::Clientbound::Transfer.read(io)

      expect(packet.host).to eq("maxport.test.com")
      expect(packet.port).to eq(max_port)
    end
  end
end
