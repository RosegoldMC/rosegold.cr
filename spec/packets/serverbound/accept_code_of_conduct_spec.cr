require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::AcceptCodeOfConduct do
  PROTOCOLS = {773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x09 after protocol 772" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x09_u8) }
    expect(described_class.supports_protocol?(772_u32)).to be_false
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_serverbound_packet(0x09_u8, 773_u32)).to eq(described_class)
  end

  it "round-trips an empty body" do
    io = Minecraft::IO::Memory.new(described_class.new.write)
    io.read_byte
    expect(described_class.read(io)).to be_a(described_class)
  end
end
