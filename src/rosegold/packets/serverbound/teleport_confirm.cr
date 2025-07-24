require "../packet"

class Rosegold::Serverbound::TeleportConfirm < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x00_u8, # MC 1.21.8,
  })

  property teleport_id : UInt32

  def initialize(@teleport_id : UInt32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write teleport_id
    end.to_slice
  end
end
