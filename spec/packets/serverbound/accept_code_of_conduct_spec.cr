require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::AcceptCodeOfConduct do
  it "uses packet ID 0x09 for protocols 773 through 776" do
    {773_u32, 774_u32, 775_u32, 776_u32}.each do |protocol|
      expect(Rosegold::Serverbound::AcceptCodeOfConduct[protocol]).to eq(0x09_u8)
    end
  end

  it "does not support protocol 772" do
    expect(Rosegold::Serverbound::AcceptCodeOfConduct.supports_protocol?(772_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Serverbound::AcceptCodeOfConduct.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_serverbound_packet(0x09_u8, 773_u32)).to eq(Rosegold::Serverbound::AcceptCodeOfConduct)
  end

  describe "packet parsing" do
    it "correctly parses a packet with no fields" do
      io = Minecraft::IO::Memory.new
      io.pos = 0

      packet = Rosegold::Serverbound::AcceptCodeOfConduct.read(io)

      expect(packet).to be_a(Rosegold::Serverbound::AcceptCodeOfConduct)
    end
  end

  describe "round-trip serialization" do
    it "can write and read an empty body" do
      original_packet = Rosegold::Serverbound::AcceptCodeOfConduct.new

      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)

      io.read_byte
      read_packet = Rosegold::Serverbound::AcceptCodeOfConduct.read(io)

      expect(read_packet).to be_a(Rosegold::Serverbound::AcceptCodeOfConduct)
    end
  end
end
