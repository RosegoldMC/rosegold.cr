require "../packet"

class Rosegold::Clientbound::UnloadChunk < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x1d_u8, # MC 1.18
    767_u32 => 0x1d_u8, # MC 1.21
    771_u32 => 0x1d_u8, # MC 1.21.6
  })

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