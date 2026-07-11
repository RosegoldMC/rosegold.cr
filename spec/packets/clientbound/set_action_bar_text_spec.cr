require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetActionBarText do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses correct packet ID per protocol" do
    expect(Rosegold::Clientbound::SetActionBarText[772_u32]).to eq(0x50_u32)
    expect(Rosegold::Clientbound::SetActionBarText[773_u32]).to eq(0x55_u32)
    expect(Rosegold::Clientbound::SetActionBarText[774_u32]).to eq(0x55_u32)
    expect(Rosegold::Clientbound::SetActionBarText[775_u32]).to eq(0x57_u32)
    expect(Rosegold::Clientbound::SetActionBarText[776_u32]).to eq(0x57_u32)
  end

  it "round-trips a simple text message" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::SetActionBarText.new(Rosegold::TextComponent.new("mining 42%"))
    bytes = packet.write

    io = Minecraft::IO::Memory.new(bytes)
    io.read_byte # packet id
    read_packet = Rosegold::Clientbound::SetActionBarText.read(io)

    expect(read_packet.text.to_s).to eq("mining 42%")
  end

  it "writes the correct packet id byte for the active protocol" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::SetActionBarText.new(Rosegold::TextComponent.new("hi"))
    bytes = packet.write

    expect(bytes[0]).to eq(0x55_u8)
  end
end
