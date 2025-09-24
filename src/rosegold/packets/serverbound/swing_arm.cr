require "../packet"

class Rosegold::Serverbound::SwingArm < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x3C_u8, # MC 1.21.8,
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
