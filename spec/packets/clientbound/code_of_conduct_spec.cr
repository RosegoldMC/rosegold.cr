require "../../spec_helper"

class CodeOfConductMockClient
  property sent_packets : Array(Rosegold::Packet) = [] of Rosegold::Packet

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::CodeOfConduct do
  it "uses packet ID 0x13 for protocols 773 through 776" do
    {773_u32, 774_u32, 775_u32, 776_u32}.each do |protocol|
      expect(Rosegold::Clientbound::CodeOfConduct[protocol]).to eq(0x13_u8)
    end
  end

  it "does not support protocol 772" do
    expect(Rosegold::Clientbound::CodeOfConduct.supports_protocol?(772_u32)).to be_false
  end

  it "supports protocols 773 through 776" do
    {773_u32, 774_u32, 775_u32, 776_u32}.each do |protocol|
      expect(Rosegold::Clientbound::CodeOfConduct.supports_protocol?(protocol)).to be_true
    end
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Clientbound::CodeOfConduct.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_clientbound_packet(0x13_u8, 773_u32)).to eq(Rosegold::Clientbound::CodeOfConduct)
  end

  describe "round-trip serialization" do
    it "round-trips the text" do
      packet = Rosegold::Clientbound::CodeOfConduct.new("Be excellent to each other.")
      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read = Rosegold::Clientbound::CodeOfConduct.read(io)

      expect(read.text).to eq("Be excellent to each other.")
    end
  end

  describe "callback" do
    it "unconditionally accepts" do
      mock_client = CodeOfConductMockClient.new
      packet = Rosegold::Clientbound::CodeOfConduct.new("Be excellent to each other.")

      packet.callback(mock_client)

      expect(mock_client.sent_packets.size).to eq(1)
      expect(mock_client.sent_packets.first).to be_a(Rosegold::Serverbound::AcceptCodeOfConduct)
    end
  end
end
