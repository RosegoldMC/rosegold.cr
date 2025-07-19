require "../packet"

class Rosegold::Clientbound::UnloadChunk < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x1d_u8, # MC 1.18 - uses separate int values
    767_u32 => 0x34_u8, # MC 1.21 - uses Position format
    771_u32 => 0x34_u8, # MC 1.21.6
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    if Client.protocol_version >= 767_u32
      # MC 1.21+ format: Position value
      pos = packet.read_bit_location
      chunk_x = pos.x >> 4
      chunk_z = pos.z >> 4
      self.new(chunk_x, chunk_z)
    else
      # MC 1.18 format: Two separate int values
      self.new(
        packet.read_int,
        packet.read_int
      )
    end
  end

  def callback(client)
    client.dimension.unload_chunk({chunk_x, chunk_z})
  end
end