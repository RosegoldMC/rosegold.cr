require "../packet"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x22_u8

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : Minecraft::NBT::Tag,
    data : Bytes,
    block_entities : Array(Chunk::BlockEntity),
    light_data : Bytes # hack. should read/write individual fields instead

  def initialize(@chunk_x, @chunk_z, @heightmaps, @data, @block_entities, @light_data); end

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
      io.write @@packet_id
      io.write_full chunk_x
      io.write_full chunk_z
      io.write heightmaps
      io.write data.size
      io.write data
      io.write block_entities.size
      block_entities.each do |be|
        io.write (((be.x & 0xf) << 4) + (be.z & 0xf)).to_u8
        io.write_full be.y.to_i16
        io.write be.type
        io.write be.nbt
      end
      io.write light_data
    end.to_slice
  end

  def callback(client)
    source = Minecraft::IO::Memory.new data
    chunk = Chunk.new source, client.dimension
    chunk.block_entities = block_entities
    chunk.light_data = light_data
    client.dimension.load_chunk ({chunk_x, chunk_z}), chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
