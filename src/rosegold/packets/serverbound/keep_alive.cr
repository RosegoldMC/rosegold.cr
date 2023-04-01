require "../packet"

class Rosegold::Serverbound::KeepAlive < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x0f_u8

  property keep_alive_id : Int64

  def initialize(@keep_alive_id : Int64); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write_full keep_alive_id
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::KeepAlive
