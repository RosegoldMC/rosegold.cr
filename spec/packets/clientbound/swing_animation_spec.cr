require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SwingAnimation do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "uses the 26.3 swing animation packet id" do
    expect(described_class.packet_id_for_protocol(777_u32)).to eq(0x7B_u32)
  end

  it "round trips the entity, hand, animation type, and duration" do
    Rosegold::Client.protocol_version = 777_u32
    animation = Rosegold::DataComponents::SwingAnimation.new(1_u32, 6_u32)
    packet = described_class.new(42, Rosegold::Hand::OffHand, animation)
    io = Minecraft::IO::Memory.new(packet.write)
    io.read_var_int

    read = described_class.read(io)

    expect(read.entity_id).to eq(42)
    expect(read.hand).to eq(Rosegold::Hand::OffHand)
    expect(read.animation.type_id).to eq(1_u32)
    expect(read.animation.duration).to eq(6_u32)
  end
end
