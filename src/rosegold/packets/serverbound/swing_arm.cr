require "../packet"

class Rosegold::Serverbound::SwingArm < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x2c_u8

  property hand : UInt8

  # 0: main hand, 1: off hand
  def initialize(@hand : UInt8 = 0); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write hand
    end.to_slice
  end
end
