require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::StartConfiguration do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::StartConfiguration[772_u32]).to eq(0x6F_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::StartConfiguration.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::StartConfiguration.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Clientbound::StartConfiguration.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_clientbound_packet(0x6F_u8, 772_u32)).to eq(Rosegold::Clientbound::StartConfiguration)
  end

  describe "packet parsing" do
    it "correctly parses packet with no fields" do
      # StartConfiguration has no fields, so just create empty packet data
      io = Minecraft::IO::Memory.new
      io.pos = 0

      packet = Rosegold::Clientbound::StartConfiguration.read(io)

      expect(packet).to be_a(Rosegold::Clientbound::StartConfiguration)
    end
  end

  describe "round-trip serialization" do
    it "can write and read start configuration packet data" do
      original_packet = Rosegold::Clientbound::StartConfiguration.new

      # Write the packet
      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)

      # Read back (skip packet ID)
      io.read_byte
      read_packet = Rosegold::Clientbound::StartConfiguration.read(io)

      expect(read_packet).to be_a(Rosegold::Clientbound::StartConfiguration)
    end
  end

  describe "callback behavior" do
    it "has implemented callback method" do
      packet = Rosegold::Clientbound::StartConfiguration.new
      expect(packet).to respond_to(:callback)
    end
  end
end
