require "../packet"

class Rosegold::Serverbound::Pong < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x1d_u8

  property ping_id : Int32

  def initialize(@ping_id : Int32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write_full ping_id
    end.to_slice
  end
end
