require "../../spec_helper"

class ConfigurationPingMockClient
  property queued_packets : Array(Rosegold::Packet) = [] of Rosegold::Packet

  def queue_packet(packet : Rosegold::Packet)
    @queued_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::ConfigurationPing do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "uses packet ID 0x05 for every supported protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Clientbound::ConfigurationPing[protocol]).to eq(0x05_u8)
    end
  end

  it "supports every enabled protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Clientbound::ConfigurationPing.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::ConfigurationPing.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Clientbound::ConfigurationPing.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_clientbound_packet(0x05_u8, 772_u32)).to eq(Rosegold::Clientbound::ConfigurationPing)
  end

  describe "round-trip serialization" do
    it "round-trips the ping id" do
      packet = Rosegold::Clientbound::ConfigurationPing.new(123456)
      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read = Rosegold::Clientbound::ConfigurationPing.read(io)

      expect(read.ping_id).to eq(123456)
    end
  end

  describe "callback" do
    it "queues a ConfigurationPong with the same id" do
      mock_client = ConfigurationPingMockClient.new
      packet = Rosegold::Clientbound::ConfigurationPing.new(654321)

      packet.callback(mock_client)

      expect(mock_client.queued_packets.size).to eq(1)
      pong = mock_client.queued_packets.first.as(Rosegold::Serverbound::ConfigurationPong)
      expect(pong.ping_id).to eq(654321)
    end
  end
end
