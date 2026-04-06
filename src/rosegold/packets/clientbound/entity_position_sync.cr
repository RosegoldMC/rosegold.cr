require "../packet"

class Rosegold::Clientbound::EntityPositionSync < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x1F_u32, # MC 1.21.8
    774_u32 => 0x23_u32, # MC 1.21.11
    775_u32 => 0x23_u32, # MC 26.1
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : UInt64,
    x : Float64,
    y : Float64,
    z : Float64,
    velocity_x : Float64,
    velocity_y : Float64,
    velocity_z : Float64,
    yaw : Float32,
    pitch : Float32

  property? on_ground : Bool

  def initialize(@entity_id, @x, @y, @z, @velocity_x, @velocity_y, @velocity_z, @yaw, @pitch, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    velocity_x = packet.read_double
    velocity_y = packet.read_double
    velocity_z = packet.read_double
    yaw = packet.read_float
    pitch = packet.read_float
    on_ground = packet.read_bool

    self.new(entity_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      buffer.write_full x
      buffer.write_full y
      buffer.write_full z
      buffer.write_full velocity_x
      buffer.write_full velocity_y
      buffer.write_full velocity_z
      buffer.write_full yaw
      buffer.write_full pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity position sync for entity ID #{entity_id}: (#{x}, #{y}, #{z})" }
    if entity = client.dimension.entities[entity_id]?
      entity.position = Vec3d.new(x, y, z)
      entity.velocity = Vec3d.new(velocity_x, velocity_y, velocity_z)
      entity.pitch = pitch
      entity.yaw = yaw
    end
  end
end
