require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetContainerContent do
  it "uses correct packet ID for protocol 772" do
    expect(Rosegold::Clientbound::SetContainerContent[772_u32]).to eq(0x12_u8)
  end

  it "supports protocol 772 only" do
    expect(Rosegold::Clientbound::SetContainerContent.supports_protocol?(772_u32)).to be_true
    expect(Rosegold::Clientbound::SetContainerContent.supports_protocol?(999_u32)).to be_false
  end

  describe "EOF error packet analysis" do
    let(:failing_packet_hex) { "12002e2e0000000000000000000000000000000000000001c907000000000000000000000000000000000010c70700000000249b09000001a20200000125000001a00707000d02011b66696e616c653a61726d6f725f746f7567686e6573735f666565744000000000000000000400001166696e616c653a61726d6f725f6665657440080000000000000004000a0427031b040904070308010a0100066974616c696300080005636f6c6f720005776869746509000565787472610a00000001080005636f6c6f720004676f6c6408000474657874000a6772657073656461776b00080004746578740018546869732061726d6f7220697320626f756e6420746f3a200010010301050a09000565787472610a000000010100066974616c69630001000a756e6465726c696e656400010004626f6c6400080005636f6c6f720004626c756501000a6f6266757363617465640001000d737472696b657468726f75676800080004746578740007476f6470726f740008000474657874000000000a0a00125075626c696342756b6b697456616c75657308002073696d706c6561646d696e6861636b733a7361685f61726d6f7572626f756e64002430313131623935642d313130632d346561312d623462322d3539616665666632393666340000018107030003da030a0327030d030804100701c907000010c70700000000" }
    let(:packet_bytes) { Bytes.new(failing_packet_hex.size // 2) { |i| failing_packet_hex[i * 2, 2].to_u8(16) } }
    let(:io) { Minecraft::IO::Memory.new(packet_bytes) }

    it "is able to read" do
      io.read_byte # Skip packet ID (0x12)

      expect { Rosegold::Clientbound::SetContainerContent.read(io) }.not_to raise_error
    end

    it "contains the right container data" do
      io.read_byte # Skip packet ID (0x12)
      container = Rosegold::Clientbound::SetContainerContent.read(io)

      expect(container.window_id).to eq(0_u8)
      expect(container.state_id).to eq(46_u32)
      # Packet is truncated, so we expect fewer slots than the declared 46
      expect(container.slots.size).to eq(46)
    end
  end
end
