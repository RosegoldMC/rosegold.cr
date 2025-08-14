require "../spec_helper"

Spectator.describe "Plugin Message Brand Integration" do
  it "should create and serialize minecraft:brand packet correctly" do
    # Test that the brand packet can be created and serialized
    brand_packet = Rosegold::Serverbound::PluginMessage.brand("Rosegold")

    expect(brand_packet.channel).to eq("minecraft:brand")
    expect(String.new(brand_packet.data)).to eq("Rosegold")

    # Test packet serialization
    original_protocol = Rosegold::Client.protocol_version
    Rosegold::Client.protocol_version = 772_u32

    bytes = brand_packet.write
    expect(bytes.size).to be > 0

    # First byte should be packet ID (0x17)
    expect(bytes[0]).to eq(0x17_u8)

    # Restore protocol
    Rosegold::Client.protocol_version = original_protocol
  end
end
