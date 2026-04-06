require "../packet"

class Rosegold::Serverbound::ChunkBatchReceived < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x0A_u32, # MC 1.21.8
    774_u32 => 0x0A_u32, # MC 1.21.11
    775_u32 => 0x0B_u32, # MC 26.1
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
