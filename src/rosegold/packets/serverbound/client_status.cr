require "../packet"

class Rosegold::Serverbound::ClientStatus < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x04_u8, # MC 1.18
    767_u32 => 0x0B_u8, # MC 1.21
    771_u32 => 0x0B_u8, # MC 1.21.6
  })

  enum Action
    Respawn; RequestStats
  end

  property action : Action

  def initialize(@action : Action = :respawn); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write action.value
    end.to_slice
  end
end
