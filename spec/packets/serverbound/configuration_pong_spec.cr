require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::ConfigurationPong do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x05 in every supported protocol" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x05_u8) }
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_serverbound_packet(0x05_u8, 772_u32)).to eq(described_class)
  end

  it "round-trips the ping id" do
    packet = described_class.new(123456)
    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte
    expect(described_class.read(io).ping_id).to eq(123456)
  end
end
