require "../packet"
require "../../world/heightmap"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x27_u8, # MC 1.21.8,
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : Array(Heightmap),
    data : Bytes,
    block_entities : Array(Chunk::BlockEntity),
    light_data : Bytes

  def initialize(@chunk_x, @chunk_z, @heightmaps, @data, @block_entities, @light_data); end

  def self.new(chunk : Chunk)
    # Convert NBT heightmaps back to array format (protocol expects array)
    heightmaps = convert_nbt_to_heightmaps(chunk.heightmaps)
    light_data = chunk.light_data
    self.new chunk.x, chunk.z, heightmaps, chunk.data, chunk.block_entities, light_data
  end

  def self.read(io)
    chunk_x = io.read_int
    chunk_z = io.read_int

    # Read Heightmaps (Prefixed Array of Heightmap)
    heightmaps_count = io.read_var_int
    heightmaps = Array(Heightmap).new(heightmaps_count) { Heightmap.read(io) }

    # Read Data (Prefixed Array of Byte)
    data = io.read_var_bytes

    # Read Block Entities (Prefixed Array)
    block_entities_count = io.read_var_int
    block_entities = Array(Chunk::BlockEntity).new(block_entities_count) do
      xz = io.read_byte
      Chunk::BlockEntity.new(
        (chunk_x * 16) + ((xz >> 4) & 0xf), # Convert chunk coord to world coord + relative
        io.read_short,
        (chunk_z * 16) + (xz & 0xf), # Convert chunk coord to world coord + relative
        io.read_var_int,
        io.read_nbt_unamed
      )
    end

    # Read Light Data
    light_data = io.getb_to_end

    self.new(chunk_x, chunk_z, heightmaps, data, block_entities, light_data)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write_full chunk_x
      io.write_full chunk_z

      # Write Heightmaps (Prefixed Array of Heightmap)
      io.write(heightmaps.size)
      heightmaps.each(&.write(io))

      # Write Data (Prefixed Array of Byte)
      io.write data.size
      io.write data

      # Write Block Entities (Prefixed Array)
      io.write block_entities.size
      block_entities.each do |block_entity|
        # Calculate relative coordinates within the chunk
        # chunk_x/z are in chunk coordinates, block_entity.x/z are in world coordinates
        chunk_world_x = chunk_x * 16
        chunk_world_z = chunk_z * 16
        relative_x = block_entity.x - chunk_world_x
        relative_z = block_entity.z - chunk_world_z
        io.write (((relative_x & 0xf) << 4) | (relative_z & 0xf)).to_u8
        io.write_full block_entity.y.to_i16
        io.write block_entity.type
        # Block entity NBT should be written as unnamed CompoundTag in protocol
        if block_entity.nbt.is_a?(Minecraft::NBT::CompoundTag)
          # Write CompoundTag type byte first
          io.write_byte 0x0A_u8
          # Then write the compound content without the type byte (it's already written)
          block_entity.nbt.as(Minecraft::NBT::CompoundTag).write(io)
        else
          # For other tag types, write normally
          io.write block_entity.nbt
        end
      end

      # Write Light Data
      io.write light_data
    end.to_slice
  end

  def callback(client)
    source = Minecraft::IO::Memory.new data
    chunk = Chunk.new chunk_x, chunk_z, source, client.dimension
    chunk.block_entities = block_entities
    # Preserve the original heightmaps from the packet by converting them to NBT format
    chunk.heightmaps = convert_heightmaps_to_nbt(heightmaps)
    chunk.light_data = light_data
    client.dimension.load_chunk chunk

    if client.physics.paused?
      spawn_chunk_x = client.player.feet.x.to_i >> 4
      spawn_chunk_z = client.player.feet.z.to_i >> 4
      if chunk_x == spawn_chunk_x && chunk_z == spawn_chunk_z
        client.physics.unpause_for_spawn_chunk
        Log.debug { "Spawn chunk loaded - physics unpaused" }
      end
    end
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end

  private def convert_heightmaps_to_nbt(heightmaps : Array(Heightmap)) : Minecraft::NBT::Tag
    # Convert array of Heightmaps to NBT CompoundTag format used by Chunk
    nbt_heightmaps = Minecraft::NBT::CompoundTag.new

    heightmaps.each do |heightmap|
      # Map heightmap types to their NBT names
      name = case heightmap.type
             when 1_u32 then "WORLD_SURFACE"
             when 2_u32 then "WORLD_SURFACE_WG"
             when 3_u32 then "OCEAN_FLOOR"
             when 4_u32 then "OCEAN_FLOOR_WG"
             when 5_u32 then "MOTION_BLOCKING"
             when 6_u32 then "MOTION_BLOCKING_NO_LEAVES"
             else            "UNKNOWN_#{heightmap.type}"
             end

      # Convert heightmap data to LongArrayTag
      nbt_heightmaps[name] = Minecraft::NBT::LongArrayTag.new(heightmap.data)
    end

    nbt_heightmaps
  end

  private def self.convert_nbt_to_heightmaps(nbt_heightmaps : Minecraft::NBT::Tag) : Array(Heightmap)
    heightmaps = Array(Heightmap).new

    return heightmaps unless nbt_heightmaps.is_a?(Minecraft::NBT::CompoundTag)

    nbt_heightmaps.as(Minecraft::NBT::CompoundTag).value.each do |name, tag|
      # Map NBT names back to heightmap type IDs
      type = case name
             when "WORLD_SURFACE"             then 1_u32
             when "WORLD_SURFACE_WG"          then 2_u32
             when "OCEAN_FLOOR"               then 3_u32
             when "OCEAN_FLOOR_WG"            then 4_u32
             when "MOTION_BLOCKING"           then 5_u32
             when "MOTION_BLOCKING_NO_LEAVES" then 6_u32
             else                                  1_u32 # Default to WORLD_SURFACE
             end

      # Extract heightmap data from LongArrayTag
      data = if tag.is_a?(Minecraft::NBT::LongArrayTag)
               tag.as(Minecraft::NBT::LongArrayTag).value
             else
               [] of Int64 # Fallback to empty array
             end

      heightmaps << Heightmap.new(type, data)
    end

    # If no heightmaps were found, create a default one
    if heightmaps.empty?
      heightmaps << Heightmap.new(1_u32, [] of Int64)
    end

    heightmaps
  end
end
