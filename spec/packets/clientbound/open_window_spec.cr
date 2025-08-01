require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::OpenWindow do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::OpenWindow[772_u32]).to eq(0x34_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::OpenWindow.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::OpenWindow.supports_protocol?(999_u32)).to be_false
  end

  describe "failing packet analysis" do
    let(:failing_packet_hex) { "3401020a0800097472616e736c6174650010636f6e7461696e65722e62617272656c00" }
    let(:packet_bytes) { Bytes.new(failing_packet_hex.size // 2) { |i| failing_packet_hex[i * 2, 2].to_u8(16) } }
    let(:io) { Minecraft::IO::Memory.new(packet_bytes) }

    it "is able to read without raising exceptions" do
      io.read_byte # Skip packet ID (0x34)

      expect { Rosegold::Clientbound::OpenWindow.read(io) }.not_to raise_error
    end

    it "parses NBT text component correctly" do
      io.read_byte # Skip packet ID (0x34)

      # This packet contains NBT text component data that was previously causing parsing errors
      # Now it should be properly parsed using NBT text component format
      window = Rosegold::Clientbound::OpenWindow.read(io)

      expect(window.window_id).to eq(1_u32)
      expect(window.window_type).to eq(2_u32)
      expect(window.window_title).to be_a(Rosegold::Chat)

      # The NBT text component should be properly parsed
      expect(window.window_title.to_s).to eq("Barrel")
      expect(window.window_title.translate).to eq("container.barrel")
    end
  end
end
