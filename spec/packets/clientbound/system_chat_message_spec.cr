require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SystemChatMessage do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SystemChatMessage[772_u32]).to eq(0x72_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::SystemChatMessage.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::SystemChatMessage.supports_protocol?(999_u32)).to be_false
  end

  describe "1.21.8" do
    let(:packet_bytes) { Bytes.new(failing_packet_hex.size // 2) { |i| failing_packet_hex[i * 2, 2].to_u8(16) } }
    let(:io) { Minecraft::IO::Memory.new(packet_bytes) }

    describe "civmc combat message (complex NBT with colors and formatting)" do
      let(:failing_packet_hex) { "720a09000565787472610a000000030100066974616c69630001000a756e6465726c696e656400010004626f6c6400080005636f6c6f72000372656401000a6f6266757363617465640001000d737472696b657468726f75676800080004746578740021596f75206861766520656e676167656420696e20636f6d6261742e205479706520000100066974616c696300080005636f6c6f720004617175610800047465787400042f637420000100066974616c696300080005636f6c6f720003726564080004746578740014746f20636865636b20796f75722074696d65722e000800047465787400000000" }

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

      it "preserves text component formatting" do
        io.read_byte # Skip packet ID (0x72)
        message = Rosegold::Clientbound::SystemChatMessage.read(io)

        # Verify that the message is a TextComponent, not a Chat
        expect(message.message).to be_a(Rosegold::TextComponent)

        # Verify formatting is preserved (this packet has red and aqua colors, but boolean formatting is set to false)
        text_component = message.message
        expect(text_component.extra).to_not be_nil
        expect(text_component.extra.try(&.any? { |e| e.color == "red" })).to be_true
        expect(text_component.extra.try(&.any? { |e| e.color == "aqua" })).to be_true
        # All boolean formatting in this packet is actually set to false/0
        expect(text_component.extra.try(&.any? { |e| e.bold == false })).to be_true
        expect(text_component.extra.try(&.any? { |e| e.italic == false })).to be_true
        expect(text_component.extra.try(&.any? { |e| e.underlined == false })).to be_true
      end
    end

    describe "snitch message with hover events (includes empty key text components)" do
      let(:failing_packet_hex) { "720a09000565787472610a00000003080004746578740009c2a762536e697463680a000b686f7665725f6576656e74080006616374696f6e000973686f775f7465787408000576616c75650040c2a7364c6f636174696f6e3a20c2a76228776f726c6429205b31333134202d3820353032305d0ac2a73647726f75703a20c2a762726f7365676f6c6474657374000008000000132020c2a7655b31333134202d3820353032305d0008000000162020c2a7615b31316d20c2a763536f757468c2a7615d00080004746578740019c2a736456e7465722020c2a7616772657073656461776b20200000" }

      it "is able to read" do
        io.read_byte # Skip packet ID (0x72)

        expect { Rosegold::Clientbound::SystemChatMessage.read(io) }.not_to raise_error
      end

      it "contains the expected message content" do
        io.read_byte # Skip packet ID (0x72)
        message = Rosegold::Clientbound::SystemChatMessage.read(io)

        expect(message.message.to_s).to eq("§6Enter  §agrepsedawk  §bSnitch  §e[1314 -8 5020]  §a[11m §cSouth§a]")
        expect(message.overlay?).to eq(false)
      end

      it "preserves all text component formatting" do
        io.read_byte # Skip packet ID (0x72)
        message = Rosegold::Clientbound::SystemChatMessage.read(io)

        # Verify that the message is a TextComponent
        expect(message.message).to be_a(Rosegold::TextComponent)

        # Verify that hover events are parsed correctly
        text_component = message.message
        expect(text_component.extra).to_not be_nil
        expect(text_component.extra.try(&.any?(&.hover_event))).to be_true
      end
    end

    describe "round-trip serialization" do
      it "can write and read simple text messages" do
        original_component = Rosegold::TextComponent.new("Hello World")
        original_message = Rosegold::Clientbound::SystemChatMessage.new(original_component, false)

        # Write the packet
        packet_bytes = original_message.write
        io = Minecraft::IO::Memory.new(packet_bytes)

        # Read back (skip packet ID)
        io.read_byte
        read_message = Rosegold::Clientbound::SystemChatMessage.read(io)

        expect(read_message.message.to_s).to eq("Hello World")
        expect(read_message.overlay?).to eq(false)
      end

      it "can write and read formatted text messages" do
        original_component = Rosegold::TextComponent.new("Formatted text")
        original_component.bold = true
        original_component.color = "red"
        original_message = Rosegold::Clientbound::SystemChatMessage.new(original_component, true)

        # Write the packet
        packet_bytes = original_message.write
        io = Minecraft::IO::Memory.new(packet_bytes)

        # Read back (skip packet ID)
        io.read_byte
        read_message = Rosegold::Clientbound::SystemChatMessage.read(io)

        expect(read_message.message.to_s).to eq("Formatted text")
        expect(read_message.message.bold).to be_true
        expect(read_message.message.color).to eq("red")
        expect(read_message.overlay?).to be_true
      end
    end

    describe "error handling" do
      it "handles malformed NBT gracefully" do
        # Create invalid NBT data
        io = Minecraft::IO::Memory.new(Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0x01])

        expect { Rosegold::Clientbound::SystemChatMessage.read(io) }.not_to raise_error

        # Reset and actually read to check fallback
        io = Minecraft::IO::Memory.new(Bytes[0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        message = Rosegold::Clientbound::SystemChatMessage.read(io)

        # Should fallback to a default message
        expect(message.message).to be_a(Rosegold::TextComponent)
      end
    end
  end
end
