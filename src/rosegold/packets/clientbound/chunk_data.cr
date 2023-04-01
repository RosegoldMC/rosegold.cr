require "../packet"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x22_u8

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : Minecraft::NBT::Tag,
    data : Bytes

  def initialize(@chunk_x, @chunk_z, @heightmaps, @data); end

  def self.read(packet)
    self.new(
      packet.read_int,
      packet.read_int,
      packet.read_nbt,
      packet.read_var_bytes
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write_full chunk_x
      buffer.write_full chunk_z
      buffer.write heightmaps
      buffer.write data.size
      buffer.write data
    end.to_slice
  end

  def callback(client)
    source = Minecraft::IO::Memory.new data
    chunk = Chunk.new source, client.dimension
    client.dimension.load_chunk ({chunk_x, chunk_z}), chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end
