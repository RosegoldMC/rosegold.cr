require "../../spec_helper"

class CodeOfConductMockClient
  property sent_packets = [] of Rosegold::Packet

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::CodeOfConduct do
  PROTOCOLS = {773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x13 after protocol 772" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x13_u8) }
    expect(described_class.supports_protocol?(772_u32)).to be_false
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_clientbound_packet(0x13_u8, 773_u32)).to eq(described_class)
  end

  it "round-trips the text" do
    packet = described_class.new("Be excellent to each other.")
    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte
    expect(described_class.read(io).text).to eq("Be excellent to each other.")
  end

  it "accepts the code of conduct" do
    client = CodeOfConductMockClient.new
    described_class.new("text").callback(client)
    expect(client.sent_packets.first).to be_a(Rosegold::Serverbound::AcceptCodeOfConduct)
  end
end
