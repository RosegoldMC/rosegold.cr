require "../packet"

class Rosegold::Clientbound::UnloadChunk < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x21_u32, # MC 1.21.8
    774_u32 => 0x25_u32, # MC 1.21.11
    775_u32 => 0x25_u32, # MC 26.1
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    # MC 1.21+ format: ChunkPos encoded as a Long
    # x = lower 32 bits, z = upper 32 bits (already chunk coordinates)
    long = packet.read_long
    chunk_x = (long & 0xFFFFFFFF).to_i32!
    chunk_z = (long >> 32).to_i32!
    self.new(chunk_x, chunk_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ format: ChunkPos encoded as a Long
      # x = lower 32 bits, z = upper 32 bits (already chunk coordinates)
      long = (chunk_x.to_i64 & 0xFFFFFFFF) | ((chunk_z.to_i64 & 0xFFFFFFFF) << 32)
      buffer.write_full(long)
    end.to_slice
  end

  def callback(client)
    client.dimension.unload_chunk({chunk_x, chunk_z})
  end
end
