require "./packet"

class Rosegold::Serverbound::PlayerPositionAndLook < Rosegold::Serverbound::Packet
  PACKET_ID = 0x12_u8

  property \
    x : Float64,
    y : Float64,
    z : Float64,
    yaw_deg : Float32,
    pitch_deg : Float32,
    on_ground : Bool

  def initialize(@x, @y, @z, @yaw_deg, @pitch_deg, @on_ground); end

  def self.new(feet : Vec3d, look_deg : LookDeg, on_ground)
    self.new(feet.x, feet.y, feet.z, look_deg.yaw, look_deg.pitch, on_ground)
  end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write yaw_deg
      buffer.write pitch_deg
      buffer.write on_ground
    end
  end
end
