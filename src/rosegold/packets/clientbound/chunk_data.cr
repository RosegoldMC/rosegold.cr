require "../packet"

class Rosegold::Clientbound::ChunkData < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x22_u8

  property \
    chunk_x : Int32,
    chunk_z : Int32,
    heightmaps : NBT::Tag,
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

  def callback(client)
    source = Minecraft::IO::Memory.new data
    chunk = World::Chunk.new source, client.dimension
    client.dimension.load_chunk ({chunk_x, chunk_z}), chunk
  end

  def inspect(io)
    io << "#<Clientbound::ChunkData " << chunk_x << "," << chunk_z << ">"
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Clientbound::ChunkData
