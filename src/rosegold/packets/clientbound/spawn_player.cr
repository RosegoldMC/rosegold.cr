require "../packet"

class Rosegold::Clientbound::SpawnPlayer < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x04_u8

  property \
    entity_id : Int32,
    uuid : UUID,
    location : Vec3d,
    look : Look

  def initialize(@entity_id, @uuid, @location, @look); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write uuid
      buffer.write location.x
      buffer.write location.y
      buffer.write location.z
      buffer.write_angle256_deg look.yaw_deg
      buffer.write_angle256_deg look.pitch_deg
    end.to_slice
  end
end
