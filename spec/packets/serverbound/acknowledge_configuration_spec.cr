require "../../spec_helper"

Spectator.describe Rosegold::Serverbound::AcknowledgeConfiguration do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Serverbound::AcknowledgeConfiguration[772_u32]).to eq(0x0F_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Serverbound::AcknowledgeConfiguration.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Serverbound::AcknowledgeConfiguration.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to PLAY state" do
    expect(Rosegold::Serverbound::AcknowledgeConfiguration.state).to eq(Rosegold::ProtocolState::PLAY)
  end

  it "is properly registered in PLAY state" do
    play_state = Rosegold::ProtocolState::PLAY
    expect(play_state.get_serverbound_packet(0x0F_u8, 772_u32)).to eq(Rosegold::Serverbound::AcknowledgeConfiguration)
  end

  describe "packet parsing" do
    it "correctly parses packet with no fields" do
      # AcknowledgeConfiguration has no fields, so just create empty packet data
      io = Minecraft::IO::Memory.new
      io.pos = 0

      packet = Rosegold::Serverbound::AcknowledgeConfiguration.read(io)

      expect(packet).to be_a(Rosegold::Serverbound::AcknowledgeConfiguration)
    end
  end

  describe "round-trip serialization" do
    it "can write and read acknowledge configuration packet data" do
      original_packet = Rosegold::Serverbound::AcknowledgeConfiguration.new

      # Write the packet
      packet_bytes = original_packet.write
      io = Minecraft::IO::Memory.new(packet_bytes)

      # Read back (skip packet ID)
      io.read_byte
      read_packet = Rosegold::Serverbound::AcknowledgeConfiguration.read(io)

      expect(read_packet).to be_a(Rosegold::Serverbound::AcknowledgeConfiguration)
    end
  end
end
