require "../packet"

class Rosegold::Serverbound::CloseWindow < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x09_u8

  property window_id : UInt16

  def initialize(@window_id : UInt16); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write window_id
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::CloseWindow
