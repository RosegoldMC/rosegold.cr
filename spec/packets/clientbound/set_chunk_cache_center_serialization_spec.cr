require "../../spec_helper"

Spectator.describe "SetChunkCacheCenter Serialization" do
  it "can serialize and deserialize basic chunk coordinates" do
    # Set protocol version for consistency
    Rosegold::Client.protocol_version = 772_u32

    original_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: 10_i32,
      chunk_z: 15_i32
    )

    # Serialize the packet
    serialized_bytes = original_packet.write

    # Create a packet reader from the serialized bytes
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Read and skip packet ID

    # Deserialize back to packet
    deserialized_packet = Rosegold::Clientbound::SetChunkCacheCenter.read(io)

    # Verify all fields match
    expect(deserialized_packet.chunk_x).to eq(original_packet.chunk_x)
    expect(deserialized_packet.chunk_z).to eq(original_packet.chunk_z)
  end

  it "can serialize and deserialize zero coordinates" do
    Rosegold::Client.protocol_version = 772_u32

    original_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: 0_i32,
      chunk_z: 0_i32
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SetChunkCacheCenter.read(io)

    # Verify zero coordinates are preserved
    expect(deserialized_packet.chunk_x).to eq(0_i32)
    expect(deserialized_packet.chunk_z).to eq(0_i32)
  end

  it "can serialize and deserialize negative coordinates" do
    Rosegold::Client.protocol_version = 772_u32

    original_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: -10_i32,
      chunk_z: -25_i32
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SetChunkCacheCenter.read(io)

    # Verify negative coordinates are preserved
    expect(deserialized_packet.chunk_x).to eq(-10_i32)
    expect(deserialized_packet.chunk_z).to eq(-25_i32)
  end

  it "produces correct packet ID for protocol 772" do
    Rosegold::Client.protocol_version = 772_u32

    packet = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: 1_i32,
      chunk_z: 1_i32
    )

    # Verify packet ID is correct for MC 1.21.8
    serialized = packet.write
    io = Minecraft::IO::Memory.new(serialized)
    packet_id = io.read_var_int

    expect(packet_id).to eq(0x57_u32)
  end

  it "handles large positive coordinates without overflow" do
    Rosegold::Client.protocol_version = 772_u32

    # Test with large but valid Int32 coordinates
    original_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: 1000000_i32,
      chunk_z: 2000000_i32
    )

    # Serialize and deserialize
    serialized_bytes = original_packet.write
    io = Minecraft::IO::Memory.new(serialized_bytes)
    io.read_var_int # Skip packet ID
    deserialized_packet = Rosegold::Clientbound::SetChunkCacheCenter.read(io)

    # Verify large coordinates are preserved
    expect(deserialized_packet.chunk_x).to eq(1000000_i32)
    expect(deserialized_packet.chunk_z).to eq(2000000_i32)
  end

  it "handles the problematic packet from logs" do
    Rosegold::Client.protocol_version = 772_u32

    # Recreate the problematic packet bytes from the logs
    # 57ffffffff0fffffffff0f = packet_id + chunk_x_varint + chunk_z_varint
    problematic_bytes = Bytes[0x57, 0xff, 0xff, 0xff, 0xff, 0x0f, 0xff, 0xff, 0xff, 0xff, 0x0f]

    # Try to parse this packet
    io = Minecraft::IO::Memory.new(problematic_bytes)
    packet_id = io.read_var_int # Should be 0x57

    expect(packet_id).to eq(0x57_u32)

    # This should not cause arithmetic overflow
    expect { Rosegold::Clientbound::SetChunkCacheCenter.read(io) }.not_to raise_error
  end

  it "perfect roundtrip preserves all data" do
    Rosegold::Client.protocol_version = 772_u32

    # Test with coordinates from the spectate server
    original = Rosegold::Clientbound::SetChunkCacheCenter.new(
      chunk_x: -1_i32, # From bot position / 16
      chunk_z: 0_i32
    )

    # Perfect roundtrip test
    serialized = original.write
    io = Minecraft::IO::Memory.new(serialized)
    io.read_var_int # Skip packet ID
    deserialized = Rosegold::Clientbound::SetChunkCacheCenter.read(io)

    # Re-serialize and compare bytes
    reserialized = deserialized.write
    expect(serialized).to eq(reserialized)
  end
end
