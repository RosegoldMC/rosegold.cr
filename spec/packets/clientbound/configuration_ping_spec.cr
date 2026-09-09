require "../../spec_helper"

class ConfigurationPingMockClient
  property sent_packets = [] of Rosegold::Packet

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::ConfigurationPing do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x05 in every supported protocol" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x05_u8) }
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_clientbound_packet(0x05_u8, 772_u32)).to eq(described_class)
  end

  it "round-trips the ping id" do
    packet = described_class.new(123456)
    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte
    expect(described_class.read(io).ping_id).to eq(123456)
  end

  it "sends the matching pong immediately" do
    client = ConfigurationPingMockClient.new
    described_class.new(654321).callback(client)

    expect(client.sent_packets.map(&.as(Rosegold::Serverbound::ConfigurationPong).ping_id)).to eq([654321])
  end
end
