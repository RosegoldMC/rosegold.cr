require "../packet"

class Rosegold::Clientbound::SetChunkCacheCenter < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x57_u8, # MC 1.21.8,
  })

  property \
    chunk_x : Int32,
    chunk_z : Int32

  def initialize(@chunk_x, @chunk_z); end

  def self.read(packet)
    chunk_x = packet.read_var_int.to_i32
    chunk_z = packet.read_var_int.to_i32
    self.new(chunk_x, chunk_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write chunk_x
      buffer.write chunk_z
    end.to_slice
  end

  def callback(client)
    Log.debug { "Set chunk cache center: (#{chunk_x}, #{chunk_z})" }
    # Update client's chunk loading center
    # client.chunk_cache_center = {chunk_x, chunk_z}
  end
end