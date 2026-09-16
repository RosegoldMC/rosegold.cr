require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::PostEffects do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips 26.3 play post effects" do
    Rosegold::Client.protocol_version = 777_u32
    original = described_class.new(["minecraft:blur", "example:underwater"] of String)

    packet = described_class.read(Minecraft::IO::Memory.new(original.write[1..]))

    expect(packet.post_effects).to eq(["minecraft:blur", "example:underwater"])
    expect(packet.write).to eq(original.write)
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x53_u32)
  end

  it "caches the complete replacement list on the client" do
    client = Rosegold::Client.new("localhost")
    client.post_effects = ["minecraft:old"]

    described_class.new(["example:new"] of String).callback(client)

    expect(client.post_effects).to eq(["example:new"])
  end
end

Spectator.describe Rosegold::Clientbound::ConfigurationPostEffects do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips 26.3 configuration post effects" do
    Rosegold::Client.protocol_version = 777_u32
    original = described_class.new(["minecraft:blur"] of String)

    packet = described_class.read(Minecraft::IO::Memory.new(original.write[1..]))

    expect(packet.post_effects).to eq(["minecraft:blur"])
    expect(packet.write).to eq(original.write)
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x0A_u32)
  end
end
