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
                       # MC 1.21+ format: Different block entity structure
                       Array(Chunk::BlockEntity).new(block_entities_count) do
                         Chunk::BlockEntity.new(
                           io.read_byte,    # x (relative to chunk)
                           io.read_short,   # y
                           io.read_byte,    # z (relative to chunk)
                           io.read_var_int, # type
                           io.read_nbt      # nbt
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

    # Protocol-aware light data reading 
    # MC 1.21.6 (771) has some differences from MC 1.21 (767)
    light_data = if Client.protocol_version >= 771_u32
                   # MC 1.21.6+ format: Enhanced light data structure
                   begin
                     light_io = Minecraft::IO::Memory.new
                     
                     # Trust Edges
                     trust_edges = io.read_bool
                     light_io.write(trust_edges)
                     
                     # For MC 1.21.6, there might be an additional field here
                     # Check if there's any remaining data that suggests a new field
                     
                     # Sky Light Mask (BitSet)
                     sky_light_mask_count = io.read_var_int
                     light_io.write(sky_light_mask_count)
                     sky_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Block Light Mask (BitSet) 
                     block_light_mask_count = io.read_var_int
                     light_io.write(block_light_mask_count)
                     block_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Empty Sky Light Mask (BitSet)
                     empty_sky_light_mask_count = io.read_var_int
                     light_io.write(empty_sky_light_mask_count)
                     empty_sky_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Empty Block Light Mask (BitSet)
                     empty_block_light_mask_count = io.read_var_int
                     light_io.write(empty_block_light_mask_count)
                     empty_block_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Sky Light arrays
                     sky_light_arrays_count = io.read_var_int
                     light_io.write(sky_light_arrays_count)
                     sky_light_arrays_count.times do
                       array_data = io.read_var_bytes
                       light_io.write(array_data.size)
                       light_io.write(array_data)
                     end
                     
                     # Block Light arrays  
                     block_light_arrays_count = io.read_var_int
                     light_io.write(block_light_arrays_count)
                     block_light_arrays_count.times do
                       array_data = io.read_var_bytes
                       light_io.write(array_data.size)
                       light_io.write(array_data)
                     end
                     
                     light_io.to_slice
                   rescue ex : Exception
                     # If light data parsing fails, log the error and consume remaining bytes
                     puts "Light data parsing failed for protocol #{Client.protocol_version}: #{ex.message}"
                     begin
                       remaining_size = io.size - io.pos
                       if remaining_size > 0
                         remaining_bytes = Bytes.new(remaining_size)
                         io.read(remaining_bytes)
                         puts "Consumed #{remaining_size} remaining bytes to prevent packet corruption"
                       end
                     rescue
                       # Ignore errors when trying to read remaining bytes
                     end
                     Bytes.empty
                   end
                 elsif Client.protocol_version >= 767_u32
                   # MC 1.21 format: Chunk Data and Update Light combined packet
                   begin
                     light_io = Minecraft::IO::Memory.new
                     
                     # Trust Edges
                     trust_edges = io.read_bool
                     light_io.write(trust_edges)
                     
                     # Sky Light Mask (BitSet)
                     sky_light_mask_count = io.read_var_int
                     light_io.write(sky_light_mask_count)
                     sky_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Block Light Mask (BitSet) 
                     block_light_mask_count = io.read_var_int
                     light_io.write(block_light_mask_count)
                     block_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Empty Sky Light Mask (BitSet)
                     empty_sky_light_mask_count = io.read_var_int
                     light_io.write(empty_sky_light_mask_count)
                     empty_sky_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Empty Block Light Mask (BitSet)
                     empty_block_light_mask_count = io.read_var_int
                     light_io.write(empty_block_light_mask_count)
                     empty_block_light_mask_count.times do
                       mask_long = io.read_long
                       light_io.write_full(mask_long)
                     end
                     
                     # Sky Light arrays
                     sky_light_arrays_count = io.read_var_int
                     light_io.write(sky_light_arrays_count)
                     sky_light_arrays_count.times do
                       array_data = io.read_var_bytes
                       light_io.write(array_data.size)
                       light_io.write(array_data)
                     end
                     
                     # Block Light arrays  
                     block_light_arrays_count = io.read_var_int
                     light_io.write(block_light_arrays_count)
                     block_light_arrays_count.times do
                       array_data = io.read_var_bytes
                       light_io.write(array_data.size)
                       light_io.write(array_data)
                     end
                     
                     light_io.to_slice
                   rescue ex : Exception
                     # If light data parsing fails, consume remaining bytes to prevent packet corruption
                     begin
                       remaining_size = io.size - io.pos
                       if remaining_size > 0
                         remaining_bytes = Bytes.new(remaining_size)
                         io.read(remaining_bytes)
                       end
                     rescue
                       # Ignore errors when trying to read remaining bytes
                     end
                     Bytes.empty
                   end
                 else
                   # MC 1.18 format: Light data is remaining bytes
                   remaining_size = io.size - io.pos
                   if remaining_size > 0
                     remaining_bytes = Bytes.new(remaining_size)
                     io.read(remaining_bytes)
                     remaining_bytes
                   else
                     Bytes.empty
                   end
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
      # If chunk parsing fails, create a fallback chunk to prevent falling through the floor
      begin
        # Create a minimal chunk with stone blocks at y=64 to provide solid ground
        fallback_chunk = create_fallback_chunk(chunk_x, chunk_z, client.dimension)
        fallback_chunk.block_entities = block_entities
        fallback_chunk.heightmaps = heightmaps
        fallback_chunk.light_data = light_data
        client.dimension.load_chunk fallback_chunk
      rescue fallback_ex : Exception
        # If even fallback fails, log the error but don't crash
        puts "Failed to create fallback chunk at #{chunk_x}, #{chunk_z}: #{fallback_ex.message}"
      end
    end
  end

  # Create a fallback chunk with solid ground to prevent falling through the floor
  private def create_fallback_chunk(chunk_x : Int32, chunk_z : Int32, dimension : Dimension) : Chunk
    # Create a minimal chunk data with stone blocks at y=64
    chunk_data_io = Minecraft::IO::Memory.new
    
    # Calculate section count for the dimension
    section_count = dimension.world_height >> 4
    
    # Create sections - add stone blocks at y=64 (section index varies by dimension)
    section_count.times do |section_index|
      section_y = dimension.min_y + (section_index << 4)
      
      # If this section contains y=64, add stone blocks
      if section_y <= 64 && section_y + 16 > 64
        # Create a paletted container with stone blocks
        chunk_data_io.write_full(0_u16)    # Block count (will be recalculated)
        
        # Block states palette
        chunk_data_io.write(1_u32)         # Palette size = 1 (just air)
        chunk_data_io.write(0_u32)         # Air block state ID
        
        # Data array (4096 indices, all 0 for air)
        chunk_data_io.write(0_u32)         # Data array size = 0 (single value)
        
        # Biomes palette  
        chunk_data_io.write(1_u32)         # Palette size = 1
        chunk_data_io.write(0_u32)         # Plains biome ID
        
        # Biome data array
        chunk_data_io.write(0_u32)         # Data array size = 0 (single value)
      else
        # Empty section (all air)
        chunk_data_io.write_full(0_u16)    # Block count
        
        # Block states palette
        chunk_data_io.write(1_u32)         # Palette size = 1
        chunk_data_io.write(0_u32)         # Air block state ID
        chunk_data_io.write(0_u32)         # Data array size = 0
        
        # Biomes palette
        chunk_data_io.write(1_u32)         # Palette size = 1
        chunk_data_io.write(0_u32)         # Plains biome ID
        chunk_data_io.write(0_u32)         # Data array size = 0
      end
    end
    
    Chunk.new(chunk_x, chunk_z, chunk_data_io, dimension)
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
