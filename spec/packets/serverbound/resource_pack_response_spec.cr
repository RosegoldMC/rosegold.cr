require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::ResourcePackResponse do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x06 in every supported protocol" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x06_u8) }
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_serverbound_packet(0x06_u8, 772_u32)).to eq(described_class)
  end

  it "round-trips every action" do
    id = UUID.new("12345678-1234-5678-9012-123456789012")
    Rosegold::Serverbound::ResourcePackResponse::Action.values.each do |action|
      io = Minecraft::IO::Memory.new(described_class.new(id, action).write)
      io.read_byte
      read = described_class.read(io)
      expect(read.id).to eq(id)
      expect(read.action).to eq(action)
    end
  end
end
