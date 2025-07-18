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
    heightmaps = io.read_nbt
    data = io.read_var_bytes
    block_entities = Array(Chunk::BlockEntity).new(io.read_var_int) do
      xz = io.read_byte
      Chunk::BlockEntity.new(
        chunk_x + ((xz >> 4) & 0xf),
        io.read_short,
        chunk_z + (xz & 0xf),
        io.read_var_int,
        io.read_nbt
      )
    end
    
    # Protocol-aware light data reading
    light_data = if Client.protocol_version >= 767_u32
      # MC 1.21+ format: Structured light data
      read_structured_light_data(io)
    else
      # MC 1.18 format: Simple light data
      io.getb_to_end
    end
    
    self.new(chunk_x, chunk_z, heightmaps, data, block_entities, light_data)
  end
  
  private def self.read_structured_light_data(io) : Bytes
    # For MC 1.21+, the light data has a more complex structure
    # According to protocol documentation, the light update section contains:
    # - Sky Light Mask (BitSet - VarInt array)
    # - Block Light Mask (BitSet - VarInt array)  
    # - Empty Sky Light Mask (BitSet - VarInt array)
    # - Empty Block Light Mask (BitSet - VarInt array)
    # - Sky Light arrays (Array of Byte Array)
    # - Block Light arrays (Array of Byte Array)
    
    # Read all the structured fields and serialize them back to bytes
    Minecraft::IO::Memory.new.tap do |light_io|
      # Read sky light mask (BitSet as VarInt array)
      sky_light_count = io.read_var_int
      light_io.write sky_light_count
      sky_light_count.times do
        mask_value = io.read_var_long
        light_io.write mask_value
      end
      
      # Read block light mask (BitSet as VarInt array)
      block_light_count = io.read_var_int
      light_io.write block_light_count
      block_light_count.times do
        mask_value = io.read_var_long
        light_io.write mask_value
      end
      
      # Read empty sky light mask (BitSet as VarInt array)
      empty_sky_count = io.read_var_int
      light_io.write empty_sky_count
      empty_sky_count.times do
        mask_value = io.read_var_long
        light_io.write mask_value
      end
      
      # Read empty block light mask (BitSet as VarInt array)
      empty_block_count = io.read_var_int
      light_io.write empty_block_count
      empty_block_count.times do
        mask_value = io.read_var_long
        light_io.write mask_value
      end
      
      # Read sky light arrays
      sky_arrays_count = io.read_var_int
      light_io.write sky_arrays_count
      sky_arrays_count.times do
        array_data = io.read_var_bytes
        light_io.write array_data.size
        light_io.write array_data
      end
      
      # Read block light arrays
      block_arrays_count = io.read_var_int
      light_io.write block_arrays_count
      block_arrays_count.times do
        array_data = io.read_var_bytes
        light_io.write array_data.size
        light_io.write array_data
      end
    end.to_slice
  rescue ex
    # If structured reading fails, fall back to reading remaining bytes
    # This ensures compatibility if the format is slightly different
    Log.debug { "Failed to read structured light data: #{ex.message}, falling back to simple read" }
    io.getb_to_end
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
    source = Minecraft::IO::Memory.new data
    chunk = Chunk.new chunk_x, chunk_z, source, client.dimension
    chunk.block_entities = block_entities
    chunk.heightmaps = heightmaps
    chunk.light_data = light_data
    client.dimension.load_chunk chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
