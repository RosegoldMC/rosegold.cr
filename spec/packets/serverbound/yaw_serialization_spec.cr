require "../../spec_helper"

Spectator.describe "Serverbound yaw serialization" do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "wraps PlayerLook yaw before serialization" do
    Rosegold::Client.protocol_version = 776_u32
    packet = Rosegold::Serverbound::PlayerLook.new(0.0_f32, 40.0_f32, true)
    packet.yaw = -197.0_f32
    io = Minecraft::IO::Memory.new(packet.write)

    expect(io.read_var_int).to eq(0x20_u32)
    expect(io.read_float).to eq(163.0_f32)
    expect(io.read_float).to eq(40.0_f32)
  end

  it "wraps PlayerPositionAndLook yaw before serialization" do
    Rosegold::Client.protocol_version = 776_u32
    packet = Rosegold::Serverbound::PlayerPositionAndLook.new(
      Rosegold::Vec3d::ORIGIN,
      Rosegold::Look.new(0.0_f32, 40.0_f32),
      true
    )
    packet.look = Rosegold::Look.new(-197.0_f32, 40.0_f32)
    io = Minecraft::IO::Memory.new(packet.write)

    expect(io.read_var_int).to eq(0x1F_u32)
    io.read_double
    io.read_double
    io.read_double
    expect(io.read_float).to eq(163.0_f32)
    expect(io.read_float).to eq(40.0_f32)
  end

  it "wraps UseItem yaw before serialization" do
    Rosegold::Client.protocol_version = 776_u32
    packet = Rosegold::Serverbound::UseItem.new(
      sequence: 42,
      pitch: 40.0_f32
    )
    packet.yaw = -197.0_f32
    io = Minecraft::IO::Memory.new(packet.write)

    expect(io.read_var_int).to eq(0x43_u32)
    expect(io.read_var_int).to eq(Rosegold::Hand::MainHand.value)
    expect(io.read_var_int).to eq(42_u32)
    expect(io.read_float).to eq(163.0_f32)
    expect(io.read_float).to eq(40.0_f32)
  end

  it "uses Minecraft's negative-inclusive boundary" do
    Rosegold::Client.protocol_version = 776_u32

    expect(Rosegold::Serverbound::PlayerLook.new(180.0_f32, 0.0_f32, true).yaw).to eq(-180.0_f32)
    expect(
      Rosegold::Serverbound::PlayerPositionAndLook.new(
        Rosegold::Vec3d::ORIGIN,
        Rosegold::Look.new(180.0_f32, 0.0_f32),
        true
      ).look.yaw
    ).to eq(-180.0_f32)
    expect(
      Rosegold::Serverbound::UseItem.new(yaw: 180.0_f32).yaw
    ).to eq(-180.0_f32)
  end
end
