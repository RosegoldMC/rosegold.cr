require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::PlayerRotation do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips yaw, pitch and relative flags for protocol 774" do
    Rosegold::Client.protocol_version = 774_u32

    packet = Rosegold::Clientbound::PlayerRotation.new(45.0_f32, -12.5_f32, true, false)
    bytes = packet.write

    expect(bytes[0]).to eq(0x47_u8)

    io = Minecraft::IO::Memory.new(bytes[1..])
    parsed = Rosegold::Clientbound::PlayerRotation.read(io)

    expect(parsed.yaw).to be_close(45.0_f32, 1e-4)
    expect(parsed.pitch).to be_close(-12.5_f32, 1e-4)
    expect(parsed.relative_yaw?).to be_true
    expect(parsed.relative_pitch?).to be_false
  end

  it "round-trips yaw and pitch for protocol 772" do
    Rosegold::Client.protocol_version = 772_u32

    packet = Rosegold::Clientbound::PlayerRotation.new(90.0_f32, 30.0_f32)
    bytes = packet.write

    expect(bytes[0]).to eq(0x42_u8)

    io = Minecraft::IO::Memory.new(bytes[1..])
    parsed = Rosegold::Clientbound::PlayerRotation.read(io)

    expect(parsed.yaw).to be_close(90.0_f32, 1e-4)
    expect(parsed.pitch).to be_close(30.0_f32, 1e-4)
  end
end
