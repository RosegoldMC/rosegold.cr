require "../../world/look"
require "../../world/vec3"
require "../packet"

class Rosegold::Serverbound::PlayerPositionAndLook < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x12_u8

  property \
    feet : Vec3d,
    look : Look
  property? \
    on_ground : Bool

  def initialize(@feet, @look, @on_ground); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write feet.x
      buffer.write feet.y
      buffer.write feet.z
      buffer.write look.yaw
      buffer.write look.pitch
      buffer.write on_ground?
    end.to_slice
  end
end
