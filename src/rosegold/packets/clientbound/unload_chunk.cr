class Rosegold::Clientbound::UnloadChunk < Rosegold::Clientbound::Packet
  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    self.new(
      packet.read_int,
      packet.read_int
    )
  end

  def callback(client)
    client.dimension.unload_chunk({chunk_x, chunk_z})
  end
end
