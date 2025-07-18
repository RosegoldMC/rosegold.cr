require "../packet"

class Rosegold::Serverbound::UseItem < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x2f_u8, # MC 1.18
    767_u32 => 0x2f_u8, # MC 1.21
    771_u32 => 0x2f_u8, # MC 1.21.6
  })

  property hand : Hand

  def initialize(@hand : Hand = Hand::MainHand); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write hand.value
    end.to_slice
  end
end