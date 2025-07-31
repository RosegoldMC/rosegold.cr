require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SystemChatMessage do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SystemChatMessage[772_u32]).to eq(0x72_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::SystemChatMessage.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::SystemChatMessage.supports_protocol?(999_u32)).to be_false
  end

  describe "civmc failing packet analysis" do
    let(:failing_packet_hex) { "720a09000565787472610a000000030100066974616c69630001000a756e6465726c696e656400010004626f6c6400080005636f6c6f72000372656401000a6f6266757363617465640001000d737472696b657468726f75676800080004746578740021596f75206861766520656e676167656420696e20636f6d6261742e205479706520000100066974616c696300080005636f6c6f720004617175610800047465787400042f637420000100066974616c696300080005636f6c6f720003726564080004746578740014746f20636865636b20796f75722074696d65722e000800047465787400000000" }
    let(:packet_bytes) { Bytes.new(failing_packet_hex.size // 2) { |i| failing_packet_hex[i * 2, 2].to_u8(16) } }
    let(:io) { Minecraft::IO::Memory.new(packet_bytes) }

    it "is able to read" do
      io.read_byte # Skip packet ID (0x72)

      expect { Rosegold::Clientbound::SystemChatMessage.read(io) }.not_to raise_error
    end

    it "contains the right message" do
      io.read_byte # Skip packet ID (0x72)
      message = Rosegold::Clientbound::SystemChatMessage.read(io)

      expect(message.message.to_s).to eq("You have engaged in combat. Type /ct to check your timer.")
      expect(message.overlay?).to eq(false)
    end
  end
end
