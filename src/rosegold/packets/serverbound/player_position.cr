require "./packet"

class Rosegold::Serverbound::PlayerPosition < Rosegold::Serverbound::Packet
  PACKET_ID = 0x11_u8

  property \
    x : Float64,
    y : Float64,
    z : Float64
  property? \
    on_ground : Bool

  def initialize(@x, @y, @z, @on_ground); end

  def self.new(feet : Vec3d, on_ground)
    self.new(feet.x, feet.y, feet.z, on_ground)
  end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write on_ground?
    end
  end
end
