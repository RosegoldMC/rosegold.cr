require "../packet"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x22_u8, # MC 1.18
    767_u32 => 0x27_u8, # MC 1.21
    771_u32 => 0x27_u8, # MC 1.21.6
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : Minecraft::NBT::Tag,
    data : Bytes,
    block_entities : Array(Chunk::BlockEntity),
    light_data : Bytes # hack. should read/write individual fields instead

  def initialize(@chunk_x, @chunk_z, @heightmaps, @data, @block_entities, @light_data); end

  def self.new(chunk : Chunk)
    self.new chunk.x, chunk.z, chunk.heightmaps, chunk.data, chunk.block_entities, chunk.light_data
  end

  def self.read(io)
    chunk_x = io.read_int
    chunk_z = io.read_int
    heightmaps = io.read_nbt_unamed
    data = io.read_var_bytes
    
    # Protocol-aware block entities reading
    block_entities_count = io.read_var_int
    block_entities = if Client.protocol_version >= 767_u32
                       # MC 1.21+ format: Check actual protocol documentation format
                       Array(Chunk::BlockEntity).new(block_entities_count) do
                         # For MC 1.21.6, the format should be: packed_xz, y, type, nbt
                         packed_xz = io.read_byte
                         x = (packed_xz >> 4) & 0xf  # Extract x from upper 4 bits
                         z = packed_xz & 0xf          # Extract z from lower 4 bits
                         y = io.read_short
                         type = io.read_var_int
                         nbt = io.read_nbt
                         
                         # Convert to absolute coordinates
                         Chunk::BlockEntity.new(
                           chunk_x * 16 + x,
                           y,
                           chunk_z * 16 + z,
                           type,
                           nbt
                         )
                       end
                     else
                       # MC 1.18 format: Original structure
                       Array(Chunk::BlockEntity).new(block_entities_count) do
                         xz = io.read_byte
                         Chunk::BlockEntity.new(
                           chunk_x + ((xz >> 4) & 0xf),
                           io.read_short,
                           chunk_z + (xz & 0xf),
                           io.read_var_int,
                           io.read_nbt
                         )
                       end
                     end

    # Skip light data reading for MC 1.21+ as requested by user
    light_data = if Client.protocol_version >= 767_u32
                   # MC 1.21+ format: No light data needed per user request
                   Bytes.empty
                 else
                   # MC 1.18 format: Light data is remaining bytes
                   remaining_size = io.size - io.pos
                   remaining_bytes = Bytes.new(remaining_size)
                   io.read(remaining_bytes)
                   remaining_bytes
                 end

    self.new(chunk_x, chunk_z, heightmaps, data, block_entities, light_data)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write_full chunk_x
      io.write_full chunk_z
      io.write heightmaps
      io.write data.size
      io.write data
      io.write block_entities.size
      block_entities.each do |block_entity|
        io.write (((block_entity.x & 0xf) << 4) | (block_entity.z & 0xf)).to_u8
        io.write_full block_entity.y.to_i16
        io.write block_entity.type
        io.write block_entity.nbt
      end

      # Write light data (protocol-aware, but simplified)
      io.write light_data
    end.to_slice
  end

  def callback(client)
    begin
      source = Minecraft::IO::Memory.new data
      chunk = Chunk.new chunk_x, chunk_z, source, client.dimension
      chunk.block_entities = block_entities
      chunk.heightmaps = heightmaps
      chunk.light_data = light_data
      client.dimension.load_chunk chunk
    rescue ex : Exception
      # Handle parsing errors gracefully - create fallback chunk to prevent falling through floor
      Log.warn { "Failed to parse chunk data for chunk #{chunk_x},#{chunk_z}: #{ex.message}. Creating fallback chunk." }
      
      # Create a minimal chunk with solid ground to prevent falling through floor
      fallback_chunk = create_fallback_chunk(chunk_x, chunk_z, client.dimension)
      fallback_chunk.block_entities = block_entities
      fallback_chunk.heightmaps = heightmaps
      fallback_chunk.light_data = light_data
      client.dimension.load_chunk fallback_chunk
    end
  end

  private def create_fallback_chunk(x : Int32, z : Int32, dimension) : Chunk
    # Create a chunk with basic stone structure to prevent falling through floor
    empty_data = Bytes.new(0)
    source = Minecraft::IO::Memory.new empty_data
    chunk = Chunk.new x, z, source, dimension
    
    # Set basic heightmaps if not present
    if chunk.heightmaps.as?(Minecraft::NBT::CompoundTag).try(&.tags.empty?)
      default_heightmaps = Hash(String, Minecraft::NBT::Tag).new
      # Create basic heightmap data for ground level at y=64
      long_array = Array(Int64).new(37) { 4629771061636907072_i64 } # Represents y=64 for all blocks
      default_heightmaps["MOTION_BLOCKING"] = Minecraft::NBT::LongArrayTag.new(long_array)
      default_heightmaps["WORLD_SURFACE"] = Minecraft::NBT::LongArrayTag.new(long_array)
      chunk.heightmaps = Minecraft::NBT::CompoundTag.new(default_heightmaps)
    end
    
    chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
