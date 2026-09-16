require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::AddTransientBlock do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips the 26.3 transient block overlay" do
    Rosegold::Client.protocol_version = 777_u32
    original = described_class.new(Rosegold::Vec3i.new(-12, 70, 345), 12_345_u32)

    packet = described_class.read(Minecraft::IO::Memory.new(original.write[1..]))

    expect(packet.location).to eq(Rosegold::Vec3i.new(-12, 70, 345))
    expect(packet.block_state).to eq(12_345_u32)
    expect(packet.write).to eq(original.write)
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x25_u32)
  end
end
