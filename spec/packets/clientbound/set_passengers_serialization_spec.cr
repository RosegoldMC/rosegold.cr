require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::SetPassengers do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips entity id and passengers for protocol 774" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::SetPassengers.new(0x7ffffffe_u32, [0x7fffffff_u32])
    bytes = packet.write

    expect(bytes[0]).to eq(0x69_u8)

    io = Minecraft::IO::Memory.new(bytes[1..])
    parsed = Rosegold::Clientbound::SetPassengers.read(io)

    expect(parsed.entity_id).to eq(0x7ffffffe_u32)
    expect(parsed.passengers).to eq([0x7fffffff_u32])
  end

  it "writes an empty passenger list" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::SetPassengers.new(0x7ffffffe_u32, [] of UInt32)
    io = Minecraft::IO::Memory.new(packet.write[1..])
    parsed = Rosegold::Clientbound::SetPassengers.read(io)

    expect(parsed.passengers).to be_empty
  end
end
