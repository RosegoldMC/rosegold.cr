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
    self.new(
      chunk_x,
      chunk_z,
      io.read_nbt,
      io.read_var_bytes,
      Array(Chunk::BlockEntity).new(io.read_var_int) do
        xz = io.read_byte
        Chunk::BlockEntity.new(
          chunk_x + ((xz >> 4) & 0xf),
          io.read_short,
          chunk_z + (xz & 0xf),
          io.read_var_int,
          io.read_nbt
        )
      end,
      io.getb_to_end
    )
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
