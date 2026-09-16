require "../../spec_helper"

Spectator.describe "26.3 entity movement packets" do
  before_each { Rosegold::Client.protocol_version = 777_u32 }
  after_each { Rosegold::Client.reset_protocol_version! }

  it "decodes stepped position paths without consuming the following field" do
    io = Minecraft::IO::Memory.new
    io.write 1_u32
    io.write 2_u32
    [Rosegold::Vec3d.new(1.0, 2.0, 3.0), Rosegold::Vec3d.new(4.0, 5.0, 6.0)].each_with_index do |position, index|
      io.write_full position.x
      io.write_full position.y
      io.write_full position.z
      io.write (index + 2).to_u32
    end
    io.write 0xA5_u8
    io.rewind

    path = Minecraft::EntityMovement::PositionPath.read(io)

    expect(path.stepped?).to be_true
    expect(path.steps.map(&.tick_offset)).to eq([2_u32, 3_u32])
    expect(path.end_position).to eq(Rosegold::Vec3d.new(4.0, 5.0, 6.0))
    expect(io.read_byte).to eq(0xA5_u8)
  end

  it "uses the packed on-ground and stepped delta stream for position moves" do
    delta = Minecraft::EntityMovement::VecDelta.new([
      Minecraft::EntityMovement::DeltaStep.new(4_i16, 0_i16, -8_i16, 2_u32),
      Minecraft::EntityMovement::DeltaStep.new(0_i16, 8_i16, 0_i16, 5_u32),
    ])
    original = Rosegold::Clientbound::EntityPosition.new(7_u64, delta, true)
    bytes = original.write
    io = Minecraft::IO::Memory.new(bytes)

    expect(io.read_byte).to eq(0x36_u8)
    read_back = Rosegold::Clientbound::EntityPosition.read(io)

    expect(read_back.position_delta.as(Minecraft::EntityMovement::VecDelta).steps.size).to eq(2)
    expect(read_back.position_delta.as(Minecraft::EntityMovement::VecDelta).steps[0].ticks).to eq(2_u32)
    expect(read_back.position_delta.as(Minecraft::EntityMovement::VecDelta).steps[1].delta_y).to eq(8_i16)
    expect(read_back.on_ground?).to be_true
    expect(io.pos).to eq(bytes.size)
  end

  it "decodes stepped deltas against each quantized intermediate base" do
    delta = Minecraft::EntityMovement::VecDelta.new([
      Minecraft::EntityMovement::DeltaStep.new(1_i16, 0_i16, 0_i16, 1_u32),
      Minecraft::EntityMovement::DeltaStep.new(1_i16, 0_i16, 0_i16, 1_u32),
    ])

    position = delta.resolve_position(Rosegold::Vec3d.new(1.0001, 2.0, 3.0))

    expect(position.x).to be_close(1.00048828125, 1e-12)
    expect(position.y).to eq(2.0)
    expect(position.z).to eq(3.0)
  end

  it "uses the 26.3 pos-rot field order" do
    original = Rosegold::Clientbound::EntityPositionAndRotation.new(
      7_u64, Minecraft::EntityMovement::VecDelta.new(4_i16, -8_i16, 12_i16), 90.0_f32, 45.0_f32, true
    )
    bytes = original.write
    io = Minecraft::IO::Memory.new(bytes)

    expect(io.read_byte).to eq(0x37_u8)
    read_back = Rosegold::Clientbound::EntityPositionAndRotation.read(io)

    expect(read_back.position_delta.as(Minecraft::EntityMovement::VecDelta).delta_y).to eq(-8_i16)
    expect(read_back.yaw).to eq(90.0_f32)
    expect(read_back.pitch).to eq(45.0_f32)
    expect(read_back.on_ground?).to be_true
    expect(io.pos).to eq(bytes.size)
  end

  it "uses the 26.3 rotation field order" do
    original = Rosegold::Clientbound::EntityRotation.new(7_u64, 90.0_f32, -45.0_f32, true)
    bytes = original.write
    io = Minecraft::IO::Memory.new(bytes)

    expect(io.read_byte).to eq(0x39_u8)
    expect(io.read_var_int).to eq(7_u32)
    expect(io.read_bool).to be_true
    expect(io.read_signed_byte).to eq(64_i8)
    expect(io.read_signed_byte).to eq(-32_i8)
    expect(io.pos).to eq(bytes.size)
  end

  it "uses PositionPath instead of velocity in position sync" do
    path = Minecraft::EntityMovement::PositionPath.new(Rosegold::Vec3d.new(1.5, -2.0, 3.25))
    original = Rosegold::Clientbound::EntityPositionSync.new(7_u64, path, 90.0_f32, -45.0_f32, true)
    bytes = original.write
    io = Minecraft::IO::Memory.new(bytes)

    expect(io.read_byte).to eq(0x23_u8)
    read_back = Rosegold::Clientbound::EntityPositionSync.read(io)

    expect(read_back.position_path.as(Minecraft::EntityMovement::PositionPath).end_position).to eq(Rosegold::Vec3d.new(1.5, -2.0, 3.25))
    expect(read_back.velocity_x).to eq(0.0)
    expect(read_back.yaw).to eq(90.0_f32)
    expect(read_back.pitch).to eq(-45.0_f32)
    expect(read_back.on_ground?).to be_true
    expect(io.pos).to eq(bytes.size)
  end
end
