require "../packet"
require "../../world/light_data"
require "../../world/heightmap"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x22_u8, # MC 1.18
    767_u32 => 0x28_u8, # MC 1.21
    769_u32 => 0x28_u8, # MC 1.21.4,
    771_u32 => 0x27_u8, # MC 1.21.6,
    772_u32 => 0x27_u8, # MC 1.21.8,
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : Array(Heightmap),
    data : Bytes,
    block_entities : Array(Chunk::BlockEntity),
    light_data : LightData

  def initialize(@chunk_x, @chunk_z, @heightmaps, @data, @block_entities, @light_data); end

  def self.new(chunk : Chunk)
    # Convert single NBT heightmap to array format (protocol expects array)
    # For now, create default heightmaps (would need proper conversion logic)
    heightmaps = [Heightmap.new(1_u32, [] of Int64)] # WORLD_SURFACE type
    light_data = if chunk.light_data.empty?
                   LightData.new
                 else
                   LightData.read(Minecraft::IO::Memory.new(chunk.light_data))
                 end
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
        chunk_x + ((xz >> 4) & 0xf),
        io.read_short,
        chunk_z + (xz & 0xf),
        io.read_var_int,
        io.read_nbt
      )
    end

    # Read Light Data
    light_data = LightData.read(io)

    self.new(chunk_x, chunk_z, heightmaps, data, block_entities, light_data)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write_full chunk_x
      io.write_full chunk_z

      # Write Heightmaps (Prefixed Array of Heightmap)
      io.write(heightmaps.size.to_u32)
      heightmaps.each { |heightmap| heightmap.write(io) }

      # Write Data (Prefixed Array of Byte)
      io.write data.size
      io.write data

      # Write Block Entities (Prefixed Array)
      io.write block_entities.size
      block_entities.each do |block_entity|
        io.write (((block_entity.x & 0xf) << 4) | (block_entity.z & 0xf)).to_u8
        io.write_full block_entity.y.to_i16
        io.write block_entity.type
        io.write block_entity.nbt
      end

      # Write Light Data
      light_data.write(io)
    end.to_slice
  end

  def callback(client)
    source = Minecraft::IO::Memory.new data
    chunk = Chunk.new chunk_x, chunk_z, source, client.dimension
    chunk.block_entities = block_entities
    # Convert heightmaps back to single NBT structure for chunk
    # TODO: Properly convert array of heightmaps to NBT format
    chunk.heightmaps = Minecraft::NBT::CompoundTag.new
    chunk.light_data = light_data.to_bytes
    client.dimension.load_chunk chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
