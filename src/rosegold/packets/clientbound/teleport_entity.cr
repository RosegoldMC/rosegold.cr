require "../packet"

class Rosegold::Clientbound::TeleportEntity < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x76_u32, # MC 1.21.8
    774_u32 => 0x7B_u32, # MC 1.21.11
    773_u32 => 0x7B_u32, # MC 1.21.9
    775_u32 => 0x7D_u32, # MC 26.1
    776_u32 => 0x7D_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  # relatives bit -> field: 0=X 1=Y 2=Z 3=YAW 4=PITCH 5=DELTA_X 6=DELTA_Y 7=DELTA_Z 8=ROTATE_DELTA
  BIT_X            = 0
  BIT_Y            = 1
  BIT_Z            = 2
  BIT_YAW          = 3
  BIT_PITCH        = 4
  BIT_DELTA_X      = 5
  BIT_DELTA_Y      = 6
  BIT_DELTA_Z      = 7
  BIT_ROTATE_DELTA = 8

  property \
    entity_id : UInt64,
    x : Float64,
    y : Float64,
    z : Float64,
    velocity_x : Float64,
    velocity_y : Float64,
    velocity_z : Float64,
    yaw : Float32,
    pitch : Float32,
    relatives : Int32

  property? on_ground : Bool

  def initialize(@entity_id, @x, @y, @z, @velocity_x, @velocity_y, @velocity_z, @yaw, @pitch, @relatives, @on_ground)
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
    relatives = packet.read_int
    on_ground = packet.read_bool

    self.new(entity_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, relatives, on_ground)
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
      buffer.write_full relatives
      buffer.write on_ground?
    end.to_slice
  end

  def relative?(bit : Int32) : Bool
    (relatives & (1 << bit)) != 0
  end

  def resolved_position(current : Vec3d) : Vec3d
    Vec3d.new(
      relative?(BIT_X) ? current.x + x : x,
      relative?(BIT_Y) ? current.y + y : y,
      relative?(BIT_Z) ? current.z + z : z,
    )
  end

  def resolved_velocity(current : Vec3d) : Vec3d
    Vec3d.new(
      relative?(BIT_DELTA_X) ? current.x + velocity_x : velocity_x,
      relative?(BIT_DELTA_Y) ? current.y + velocity_y : velocity_y,
      relative?(BIT_DELTA_Z) ? current.z + velocity_z : velocity_z,
    )
  end

  def resolved_yaw(current : Float32) : Float32
    relative?(BIT_YAW) ? current + yaw : yaw
  end

  def resolved_pitch(current : Float32) : Float32
    relative?(BIT_PITCH) ? current + pitch : pitch
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?
    return unless entity

    entity.position = resolved_position(entity.position)
    entity.velocity = resolved_velocity(entity.velocity)
    entity.yaw = resolved_yaw(entity.yaw)
    entity.pitch = resolved_pitch(entity.pitch)
    entity.on_ground = on_ground?
  end
end
