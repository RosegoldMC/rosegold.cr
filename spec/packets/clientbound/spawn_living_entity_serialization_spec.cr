require "../../spec_helper"

Spectator.describe "SpawnEntity Serialization" do
  it "can serialize and deserialize a basic spawn entity packet" do
    # Set protocol version for consistency
    Rosegold::Client.protocol_version = 772_u32

    original_packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 123_u32,
      uuid: UUID.new("550e8400-e29b-41d4-a716-446655440000"),
      entity_type: 119_u32, # Player entity type
      x: 8.5,
      y: 241.0,
      z: 9.5,
      pitch: 0.0_f64,
      yaw: 0.0_f64,
      head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16,
      velocity_y: 0_i16,
      velocity_z: 0_i16
    )

    # Serialize the packet
    serialized_bytes = original_packet.write

    # Create a packet reader from the serialized bytes
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Read and skip packet ID

    # Deserialize back to packet
    deserialized_packet = Rosegold::Clientbound::SpawnEntity.read(io)

    # Verify all fields match
    expect(deserialized_packet.entity_id).to eq(original_packet.entity_id)
    expect(deserialized_packet.uuid).to eq(original_packet.uuid)
    expect(deserialized_packet.entity_type).to eq(original_packet.entity_type)
    expect(deserialized_packet.x).to eq(original_packet.x)
    expect(deserialized_packet.y).to eq(original_packet.y)
    expect(deserialized_packet.z).to eq(original_packet.z)
    expect(deserialized_packet.pitch).to eq(original_packet.pitch)
    expect(deserialized_packet.yaw).to eq(original_packet.yaw)
    expect(deserialized_packet.head_yaw).to eq(original_packet.head_yaw)
    expect(deserialized_packet.data).to eq(original_packet.data)
    expect(deserialized_packet.velocity_x).to eq(original_packet.velocity_x)
    expect(deserialized_packet.velocity_y).to eq(original_packet.velocity_y)
    expect(deserialized_packet.velocity_z).to eq(original_packet.velocity_z)
  end

  it "can serialize and deserialize with different entity types" do
    Rosegold::Client.protocol_version = 772_u32

    # Test with a different entity type (zombie)
    original_packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 456_u32,
      uuid: UUID.new("123e4567-e89b-12d3-a456-426614174000"),
      entity_type: 116_u32, # Zombie entity type
      x: 10.0,
      y: 64.0,
      z: 20.0,
      pitch: 0.0_f64,
      yaw: 0.0_f64,
      head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16,
      velocity_y: 0_i16,
      velocity_z: 0_i16
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SpawnEntity.read(io)

    # Verify all fields match
    expect(deserialized_packet.entity_id).to eq(456_u32)
    expect(deserialized_packet.uuid).to eq(UUID.new("123e4567-e89b-12d3-a456-426614174000"))
    expect(deserialized_packet.entity_type).to eq(116_u32)
    expect(deserialized_packet.x).to eq(10.0)
    expect(deserialized_packet.y).to eq(64.0)
    expect(deserialized_packet.z).to eq(20.0)
    expect(deserialized_packet.pitch).to eq(0.0_f64)
    expect(deserialized_packet.yaw).to eq(0.0_f64)
    expect(deserialized_packet.head_yaw).to eq(0.0_f64)
    expect(deserialized_packet.data).to eq(0_u32)
  end

  it "can serialize and deserialize with zero values" do
    Rosegold::Client.protocol_version = 772_u32

    # Test with all zero/minimal values
    original_packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 0_u32,
      uuid: UUID.new("00000000-0000-0000-0000-000000000000"),
      entity_type: 0_u32,
      x: 0.0,
      y: 0.0,
      z: 0.0,
      pitch: 0.0_f64,
      yaw: 0.0_f64,
      head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16,
      velocity_y: 0_i16,
      velocity_z: 0_i16
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SpawnEntity.read(io)

    # Verify all zero values are preserved
    expect(deserialized_packet.entity_id).to eq(0_u32)
    expect(deserialized_packet.uuid).to eq(UUID.new("00000000-0000-0000-0000-000000000000"))
    expect(deserialized_packet.entity_type).to eq(0_u32)
    expect(deserialized_packet.x).to eq(0.0)
    expect(deserialized_packet.y).to eq(0.0)
    expect(deserialized_packet.z).to eq(0.0)
    expect(deserialized_packet.pitch).to eq(0.0_f64)
    expect(deserialized_packet.yaw).to eq(0.0_f64)
    expect(deserialized_packet.head_yaw).to eq(0.0_f64)
    expect(deserialized_packet.data).to eq(0_u32)
  end

  it "produces correct packet ID for protocol 772" do
    Rosegold::Client.protocol_version = 772_u32

    packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 1_u32,
      uuid: UUID.random,
      entity_type: 1_u32,
      x: 0.0, y: 0.0, z: 0.0,
      pitch: 0.0_f64, yaw: 0.0_f64, head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16, velocity_y: 0_i16, velocity_z: 0_i16
    )

    # Verify packet ID is correct for MC 1.21.8
    serialized = packet.write
    io = Minecraft::IO::Memory.new(serialized)
    packet_id = io.read_var_int

    expect(packet_id).to eq(0x01_u32)
  end

  it "handles fractional coordinates correctly" do
    Rosegold::Client.protocol_version = 772_u32

    # Test with precise fractional coordinates
    original_packet = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 42_u32,
      uuid: UUID.new("12345678-1234-5678-9abc-123456789abc"),
      entity_type: 50_u32,
      x: 12.34,
      y: 56.78,
      z: 90.12,
      pitch: 0.0_f64,
      yaw: 0.0_f64,
      head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16,
      velocity_y: 0_i16,
      velocity_z: 0_i16
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SpawnEntity.read(io)

    # Verify fractional precision is maintained
    expect(deserialized_packet.x).to be_close(12.34, 1e-10)
    expect(deserialized_packet.y).to be_close(56.78, 1e-10)
    expect(deserialized_packet.z).to be_close(90.12, 1e-10)
    expect(deserialized_packet.pitch).to be_close(0.0_f64, 1e-6)
    expect(deserialized_packet.yaw).to be_close(0.0_f64, 1e-6)
    expect(deserialized_packet.head_yaw).to be_close(0.0_f64, 1e-6)
  end

  it "perfect roundtrip preserves all data" do
    Rosegold::Client.protocol_version = 772_u32

    # Test realistic SpectateBot spawn values
    original = Rosegold::Clientbound::SpawnEntity.new(
      entity_id: 1234_u32,
      uuid: UUID.new("550e8400-e29b-41d4-a716-446655440000"),
      entity_type: 119_u32,     # Player entity type
      x: 8.5, y: 241.0, z: 9.5, # SpectateBot spawn coordinates
      pitch: 0.0_f64, yaw: 0.0_f64, head_yaw: 0.0_f64,
      data: 0_u32,
      velocity_x: 0_i16, velocity_y: 0_i16, velocity_z: 0_i16
    )

    # Perfect roundtrip test
    serialized = original.write
    io = Minecraft::IO::Memory.new(serialized)
    io.read_var_int # Skip packet ID
    deserialized = Rosegold::Clientbound::SpawnEntity.read(io)

    # Re-serialize and compare bytes
    reserialized = deserialized.write
    expect(serialized).to eq(reserialized)
  end
end
