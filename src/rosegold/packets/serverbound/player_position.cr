require "../packet"

class Rosegold::Serverbound::PlayerPosition < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x11_u8

  property \
    x : Float64,
    y : Float64,
    z : Float64,
    on_ground : Bool

  def initialize(@x, @y, @z, @on_ground); end

  def self.new(feet : Vec3d, on_ground)
    self.new(feet.x, feet.y, feet.z, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write on_ground
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::PlayerPosition
