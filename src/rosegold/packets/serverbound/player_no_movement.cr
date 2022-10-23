require "../packet"

class Rosegold::Serverbound::PlayerNoMovement < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x14_u8

  property on_ground : Bool

  def initialize(@on_ground); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write on_ground
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::PlayerNoMovement
