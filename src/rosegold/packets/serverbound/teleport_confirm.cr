require "../packet"

class Rosegold::Serverbound::TeleportConfirm < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x00_u8

  property teleport_id : UInt32

  def initialize(@teleport_id : UInt32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write teleport_id
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::TeleportConfirm
