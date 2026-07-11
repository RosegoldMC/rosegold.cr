require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::ResourcePackResponse do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "uses packet ID 0x06 for every supported protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Serverbound::ResourcePackResponse[protocol]).to eq(0x06_u8)
    end
  end

  it "supports every enabled protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Serverbound::ResourcePackResponse.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Serverbound::ResourcePackResponse.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Serverbound::ResourcePackResponse.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_serverbound_packet(0x06_u8, 772_u32)).to eq(Rosegold::Serverbound::ResourcePackResponse)
  end

  describe "round-trip serialization" do
    it "round-trips every action" do
      id = UUID.new("12345678-1234-5678-9012-123456789012")

      Rosegold::Serverbound::ResourcePackResponse::Action.values.each do |action|
        packet = Rosegold::Serverbound::ResourcePackResponse.new(id, action)
        io = Minecraft::IO::Memory.new(packet.write)
        io.read_byte
        read = Rosegold::Serverbound::ResourcePackResponse.read(io)

        expect(read.id).to eq(id)
        expect(read.action).to eq(action)
      end
    end
  end
end
