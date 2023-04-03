require "../packet"

# Respawn: action=0
class Rosegold::Serverbound::ClientStatus < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x04_u8

  property action : UInt8

  def initialize(@action : UInt8 = 0); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write action
    end.to_slice
  end
end
