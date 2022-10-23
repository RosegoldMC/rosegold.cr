require "../packet"

class Rosegold::Serverbound::PlayerLook < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x13_u8

  property \
    yaw_deg : Float32,
    pitch_deg : Float32,
    on_ground : Bool

  def initialize(@yaw_deg, @pitch_deg, @on_ground); end

  def self.new(look : Look, on_ground)
    self.new(look.yaw_deg, look.pitch_deg, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write yaw_deg
      buffer.write pitch_deg
      buffer.write on_ground
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::PlayerLook
