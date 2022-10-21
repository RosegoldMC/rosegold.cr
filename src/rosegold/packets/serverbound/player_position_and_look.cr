require "./packet"
require "../../world/look"
require "../../world/vec3"

class Rosegold::Serverbound::PlayerPositionAndLook < Rosegold::Serverbound::Packet
  PACKET_ID = 0x12_u8

  property \
    feet : Vec3d,
    look : Look,
    on_ground : Bool

  def initialize(@feet, @look, @on_ground); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write feet.x
      buffer.write feet.y
      buffer.write feet.z
      buffer.write look.yaw_deg
      buffer.write look.pitch_deg
      buffer.write on_ground
    end
  end
end
