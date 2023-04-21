require "../../world/look"
require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::EntityTeleport < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x62_u8

  property \
    entity_id : UInt64,
    location : Vec3d,
    look : Look
  property? \
    on_ground : Bool

  def initialize(@entity_id, @location, @look, @on_ground = true); end

  def self.read(packet)
    self.new(
      packet.read_var_long,
      Vec3d.new(
        packet.read_double,
        packet.read_double,
        packet.read_double),
      Look.new(
        packet.read_angle256_deg,
        packet.read_angle256_deg),
      packet.read_bool
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write location.x
      buffer.write location.y
      buffer.write location.z
      buffer.write_angle256_deg look.yaw
      buffer.write_angle256_deg look.pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity teleport packet for unknown entity ID #{entity_id}" }
      return
    end

    entity.position = location
    entity.yaw = look.yaw
    entity.pitch = look.pitch

    entity.update_passengers client
  end
end
