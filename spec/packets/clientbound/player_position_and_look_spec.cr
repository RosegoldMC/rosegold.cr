require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::PlayerPositionAndLook do
  let(:io) { Minecraft::IO::Memory.new(File.read(file)) }
  let(:file) { File.expand_path("../../../fixtures/packets/clientbound/player_position_and_look.mcpacket", __FILE__) }
  let(:file_slice) { File.read(file).to_slice }

  # Set protocol to 758 to match the fixture file
  before_each do
    Rosegold::Client.protocol_version = 758_u32
  end

  after_each do
    # Reset to default
    Rosegold::Client.protocol_version = 771_u32
  end

  it "parses the packet" do
    io.read_byte
    packet = Rosegold::Clientbound::PlayerPositionAndLook.read(io)

    expect(packet.x_raw).to be_a(Float64)
    expect(packet.y_raw).to be_a(Float64)
    expect(packet.z_raw).to be_a(Float64)
    expect(packet.yaw_raw).to be_a(Float32)
    expect(packet.pitch_raw).to be_a(Float32)
    expect(packet.relative_flags).to be_a(UInt8)
    expect(packet.teleport_id).to be_a(UInt32)

    expect(packet.x_raw).to eq(-5010.449320949349)
    expect(packet.y_raw).to eq(-53.0)
    expect(packet.z_raw).to eq(704.3544759367975)
    expect(packet.yaw_raw).to eq(Float32.new(-88.24123))
    expect(packet.pitch_raw).to eq(Float32.new(-29.699776))
    expect(packet.relative_flags).to eq(0)
    expect(packet.teleport_id).to eq(2)
  end

  it "writes packet the same after parsing" do
    io.read_byte

    expect(Rosegold::Clientbound::PlayerPositionAndLook.read(io).write).to eq file_slice
  end
end
