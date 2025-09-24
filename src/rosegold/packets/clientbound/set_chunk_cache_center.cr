require "../packet"

class Rosegold::Clientbound::SetChunkCacheCenter < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x57_u8, # MC 1.21.8,
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    # Read VarInt and safely convert to Int32, handling overflow
    chunk_x_raw = packet.read_var_int
    chunk_z_raw = packet.read_var_int

    # Convert UInt32 to Int32 safely using unsafe cast to handle two's complement
    chunk_x = chunk_x_raw.unsafe_as(Int32)
    chunk_z = chunk_z_raw.unsafe_as(Int32)

    self.new(chunk_x, chunk_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # Convert Int32 to UInt32 for VarInt encoding to avoid overflow
      buffer.write chunk_x.unsafe_as(UInt32)
      buffer.write chunk_z.unsafe_as(UInt32)
    end.to_slice
  end

  def callback(client)
    Log.debug { "Set chunk cache center: (#{chunk_x}, #{chunk_z})" }
    # Update client's chunk loading center
    # client.chunk_cache_center = {chunk_x, chunk_z}
  end
end
