require "../../world/look"
require "../../world/vec3"
require "../packet"

class Rosegold::Serverbound::PlayerPositionAndLook < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x38_u8, # MC 1.18
    767_u32 => 0x1B_u8, # MC 1.21
    771_u32 => 0x1B_u8, # MC 1.21.6
  })

  property \
    feet : Vec3d,
    look : Look
  property? \
    on_ground : Bool

  def initialize(@feet, @look, @on_ground); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write feet.x
      buffer.write feet.y
      buffer.write feet.z
      buffer.write look.yaw
      buffer.write look.pitch
      buffer.write on_ground?
    end.to_slice
  end
end
