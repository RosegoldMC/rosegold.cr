require "../packet"

# MC 26.1+ only: dedicated attack packet (split from InteractEntity)
class Rosegold::Serverbound::Attack < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    775_u32 => 0x01_u32, # MC 26.1
  })

  property entity_id : UInt64

  def initialize(@entity_id : UInt64); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
    end.to_slice
  end
end
