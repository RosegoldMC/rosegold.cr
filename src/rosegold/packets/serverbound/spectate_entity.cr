require "../packet"

# MC 26.1+: spectate by entity ID (different from TeleportToEntity)
class Rosegold::Serverbound::SpectateEntity < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    775_u32 => 0x3E_u32, # MC 26.1
  })

  property entity_id : UInt32

  def initialize(@entity_id : UInt32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
    end.to_slice
  end
end
