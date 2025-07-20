require "../packet"

class Rosegold::Serverbound::ChunkBatchReceived < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    767_u32 => 0x0A_u8, # MC 1.21
    771_u32 => 0x0A_u8, # MC 1.21.6
  })

  property chunks_per_tick : Float32

  def initialize(@chunks_per_tick : Float32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write chunks_per_tick
    end.to_slice
  end
end
