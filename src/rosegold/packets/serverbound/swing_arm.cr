require "../packet"

class Rosegold::Serverbound::SwingArm < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x2c_u8

  property hand : Hand

  def initialize(@hand : Hand = Hand::MainHand); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write hand.value
    end.to_slice
  end
end
