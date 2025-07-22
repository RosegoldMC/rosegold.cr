require "../packet"

class Rosegold::Serverbound::LoginPluginResponse < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x02_u8, # MC 1.18
    767_u32 => 0x02_u8, # MC 1.21
    769_u32 => 0x02_u8, # MC 1.21.4,
    771_u32 => 0x02_u8, # MC 1.21.6,
  })
  class_getter state = Rosegold::ProtocolState::LOGIN

  property message_id : UInt32

  def initialize(@message_id); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write message_id
      buffer.write false
    end.to_slice
  end
end
