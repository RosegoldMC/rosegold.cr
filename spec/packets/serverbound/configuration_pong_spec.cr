require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::ConfigurationPong do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "uses packet ID 0x05 for every supported protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Serverbound::ConfigurationPong[protocol]).to eq(0x05_u8)
    end
  end

  it "supports every enabled protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Serverbound::ConfigurationPong.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Serverbound::ConfigurationPong.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Serverbound::ConfigurationPong.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_serverbound_packet(0x05_u8, 772_u32)).to eq(Rosegold::Serverbound::ConfigurationPong)
  end

  describe "round-trip serialization" do
    it "round-trips the ping id" do
      packet = Rosegold::Serverbound::ConfigurationPong.new(123456)
      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read = Rosegold::Serverbound::ConfigurationPong.read(io)

      expect(read.ping_id).to eq(123456)
    end
  end
end
