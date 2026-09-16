require "../../spec_helper"

Spectator.describe "SynchronizePlayerPosition Serialization" do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "round-trips the 26.3 player-position fixture" do
    Rosegold::Client.protocol_version = 777_u32

    original_bytes = "49ac023ff4000000000000c004000000000000400e0000000000003fe0000000000000bff0000000000000000000000000000042340000c1f0000000000009".hexbytes
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.read(Minecraft::IO::Memory.new(original_bytes[1..]))

    expect(packet.write).to eq(original_bytes)
  end

  it "acknowledges a 26.3 position with the resolved player pose" do
    Rosegold::Client.protocol_version = 777_u32
    client = SynchronizePlayerPositionMockClient.new
    client.player.feet = Rosegold::Vec3d.new(10.0, 20.0, 30.0)
    client.player.look = Rosegold::Look.new(90.0_f32, 10.0_f32)

    Rosegold::Clientbound::SynchronizePlayerPosition.new(
      1.25, -2.5, 3.75, 45.0_f32, -30.0_f32, 0x09, 300_u32
    ).callback(client)

    acknowledgement = client.queued_packets.first.as(Rosegold::Serverbound::TeleportConfirm)
    expect(acknowledgement.teleport_id).to eq(300_u32)
    expect(acknowledgement.x).to eq(11.25)
    expect(acknowledgement.y).to eq(-2.5)
    expect(acknowledgement.z).to eq(3.75)
    expect(acknowledgement.yaw).to eq(135.0_f32)
    expect(acknowledgement.pitch).to eq(-30.0_f32)
  end

  it "can read and write SynchronizePlayerPosition packet with perfect equality" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Captured SynchronizePlayerPosition packet data from log
    # 2025-08-05T04:22:43.889589Z   WARN - Packet bytes (62 bytes)
    hex_data = "41013fe0000000000000c04e0000000000003ff8000000000000000000000000000000000000000000000000000000000000c33400000000000000000000"

    # Convert hex string to bytes
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte is 0x41)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.read(io)

    # Write the packet back out
    rewritten_bytes = packet.write

    # Compare the bytes for perfect roundtrip
    expect(rewritten_bytes).to eq(original_bytes)
  end

  it "can parse minecraft:synchronize_player_position values correctly" do
    # Set protocol version
    Rosegold::Client.protocol_version = 772_u32

    # Same packet data as above test
    hex_data = "41013fe0000000000000c04e0000000000003ff8000000000000000000000000000000000000000000000000000000000000c33400000000000000000000"
    original_bytes = hex_data.hexbytes

    # Parse the packet
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.read(io)

    # Validate specific values from the hex data:
    # Teleport ID=1, Pos=(0.5, -60.0, 1.5), Velocity=(0,0,0), Yaw=-180°, Pitch=0°, Flags=0
    expect(packet.teleport_id).to eq(1_u32)
    expect(packet.x_raw).to be_close(0.5, 0.001)
    expect(packet.y_raw).to be_close(-60.0, 0.001)
    expect(packet.z_raw).to be_close(1.5, 0.001)
    expect(packet.velocity_x).to eq(0.0)
    expect(packet.velocity_y).to eq(0.0)
    expect(packet.velocity_z).to eq(0.0)
    expect(packet.yaw_raw).to be_close(-180.0, 0.001)
    expect(packet.pitch_raw).to eq(0.0)
    expect(packet.relative_flags).to eq(0_i32)
  end
end

class SynchronizePlayerPositionMockPhysics
  def handle_reset; end
end

class SynchronizePlayerPositionMockClient
  getter player = Rosegold::Player.new
  getter physics = SynchronizePlayerPositionMockPhysics.new
  getter queued_packets = [] of Rosegold::Serverbound::Packet

  def queue_packet(packet : Rosegold::Serverbound::Packet)
    queued_packets << packet
  end

  def emit_event(event : Rosegold::Event); end
end
