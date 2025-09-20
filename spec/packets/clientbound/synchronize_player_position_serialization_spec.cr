require "../../spec_helper"

Spectator.describe "SynchronizePlayerPosition Serialization" do
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
    expect(packet.relative_flags).to eq(0_u8)
  end
end
