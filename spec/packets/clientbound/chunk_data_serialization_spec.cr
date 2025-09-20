require "../../spec_helper"

Spectator.describe "ChunkData Serialization" do
  it "can read ChunkData packet and verify structural consistency" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Read the captured ChunkData packet hex data from fixture
    hex_data = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/chunk_data.hex")).strip
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte should be 0x27)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::ChunkData.read(io)

    # Verify we can parse the real packet correctly
    expect(packet.chunk_x).to be_a(Int32)
    expect(packet.chunk_z).to be_a(Int32)
    expect(packet.heightmaps.size).to be > 0
    expect(packet.data.size).to be > 0
    expect(packet.block_entities.size).to be >= 0
    expect(packet.light_data.size).to be > 0

    # Write the packet back out and verify size match
    rewritten_bytes = packet.write
    expect(rewritten_bytes.size).to eq(original_bytes.size)

    # Test that we can read our own written packet back
    io2 = Minecraft::IO::Memory.new(rewritten_bytes[1..])
    reparsed_packet = Rosegold::Clientbound::ChunkData.read(io2)

    # Verify essential structural consistency after rewrite
    expect(reparsed_packet.chunk_x).to eq(packet.chunk_x)
    expect(reparsed_packet.chunk_z).to eq(packet.chunk_z)
    expect(reparsed_packet.heightmaps.size).to eq(packet.heightmaps.size)
    expect(reparsed_packet.data.size).to eq(packet.data.size)
    expect(reparsed_packet.block_entities.size).to eq(packet.block_entities.size)
  end

  it "can simulate full client lifecycle: receive packet, store chunk, re-serialize" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Read and parse original packet
    original_hex = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/chunk_data.hex")).strip
    original_bytes = original_hex.hexbytes
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    received_packet = Rosegold::Clientbound::ChunkData.read(io)

    # Simulate storing the chunk in the client (like the callback method does)
    source = Minecraft::IO::Memory.new received_packet.data
    dimension_nbt = Minecraft::NBT::CompoundTag.new
    dimension_nbt["min_y"] = Minecraft::NBT::IntTag.new(-64)
    dimension_nbt["height"] = Minecraft::NBT::IntTag.new(384)
    dimension = Rosegold::Dimension.new "minecraft:overworld", dimension_nbt
    chunk = Rosegold::Chunk.new received_packet.chunk_x, received_packet.chunk_z, source, dimension
    chunk.block_entities = received_packet.block_entities
    chunk.heightmaps = convert_heightmaps_to_nbt(received_packet.heightmaps)
    chunk.light_data = received_packet.light_data

    # Re-create packet from stored chunk (like ChunkData.new(chunk) would do)
    heightmaps_array = convert_nbt_to_heightmaps(chunk.heightmaps)
    resent_packet = Rosegold::Clientbound::ChunkData.new(
      chunk.x, chunk.z, heightmaps_array, chunk.data, chunk.block_entities, chunk.light_data
    )
    resent_bytes = resent_packet.write

    # Verify perfect byte-for-byte match for vanilla client compatibility
    expect(resent_bytes.size).to eq(original_bytes.size)
    expect(resent_bytes).to eq(original_bytes)
  end

  it "can create and serialize ChunkData packet from scratch" do
    Rosegold::Client.protocol_version = 772_u32

    # Create test data
    chunk_x = 5_i32
    chunk_z = -3_i32
    heightmaps = [Rosegold::Heightmap.new(1_u32, [0_i64, 0_i64, 0_i64])]
    test_data = Bytes[1, 2, 3, 4]
    block_entities = [] of Rosegold::Chunk::BlockEntity
    light_data = Bytes[1, 2, 3, 4, 5, 6, 7, 8]

    # Create packet
    packet = Rosegold::Clientbound::ChunkData.new(
      chunk_x, chunk_z, heightmaps, test_data, block_entities, light_data
    )

    # Test serialization roundtrip
    written_bytes = packet.write
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::ChunkData.read(io)

    expect(parsed_packet.chunk_x).to eq(chunk_x)
    expect(parsed_packet.chunk_z).to eq(chunk_z)
    expect(parsed_packet.heightmaps.size).to eq(1)
    expect(parsed_packet.data.size).to eq(4)
    expect(parsed_packet.block_entities.size).to eq(0)
    expect(parsed_packet.light_data.size).to eq(8)
  end

  private def convert_heightmaps_to_nbt(heightmaps : Array(Rosegold::Heightmap)) : Minecraft::NBT::Tag
    nbt_heightmaps = Minecraft::NBT::CompoundTag.new

    heightmaps.each do |heightmap|
      name = case heightmap.type
             when 1_u32 then "WORLD_SURFACE"
             when 2_u32 then "WORLD_SURFACE_WG"
             when 3_u32 then "OCEAN_FLOOR"
             when 4_u32 then "OCEAN_FLOOR_WG"
             when 5_u32 then "MOTION_BLOCKING"
             when 6_u32 then "MOTION_BLOCKING_NO_LEAVES"
             else            "UNKNOWN_#{heightmap.type}"
             end

      nbt_heightmaps[name] = Minecraft::NBT::LongArrayTag.new(heightmap.data)
    end

    nbt_heightmaps
  end

  private def convert_nbt_to_heightmaps(nbt_heightmaps : Minecraft::NBT::Tag) : Array(Rosegold::Heightmap)
    heightmaps = Array(Rosegold::Heightmap).new

    return heightmaps unless nbt_heightmaps.is_a?(Minecraft::NBT::CompoundTag)

    nbt_heightmaps.as(Minecraft::NBT::CompoundTag).value.each do |name, tag|
      type = case name
             when "WORLD_SURFACE"             then 1_u32
             when "WORLD_SURFACE_WG"          then 2_u32
             when "OCEAN_FLOOR"               then 3_u32
             when "OCEAN_FLOOR_WG"            then 4_u32
             when "MOTION_BLOCKING"           then 5_u32
             when "MOTION_BLOCKING_NO_LEAVES" then 6_u32
             else                                  1_u32
             end

      data = if tag.is_a?(Minecraft::NBT::LongArrayTag)
               tag.as(Minecraft::NBT::LongArrayTag).value
             else
               [] of Int64
             end

      heightmaps << Rosegold::Heightmap.new(type, data)
    end

    if heightmaps.empty?
      heightmaps << Rosegold::Heightmap.new(1_u32, [] of Int64)
    end

    heightmaps
  end
end
