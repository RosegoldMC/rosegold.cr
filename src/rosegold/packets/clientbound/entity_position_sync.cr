require "../packet"
require "../../../minecraft/entity_movement"

class Rosegold::Clientbound::EntityPositionSync < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x1F_u32, # MC 1.21.8
    774_u32 => 0x23_u32, # MC 1.21.11
    773_u32 => 0x23_u32, # MC 1.21.9
    775_u32 => 0x23_u32, # MC 26.1
    776_u32 => 0x23_u32, # MC 26.2
    777_u32 => 0x23_u32,
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
  getter position_path : Minecraft::EntityMovement::PositionPath?

  def initialize(@entity_id, @x, @y, @z, @velocity_x, @velocity_y, @velocity_z, @yaw, @pitch, @on_ground)
    @position_path = nil
  end

  def initialize(@entity_id, @position_path : Minecraft::EntityMovement::PositionPath, @yaw, @pitch, @on_ground)
    @x = position_path.end_position.x
    @y = position_path.end_position.y
    @z = position_path.end_position.z
    @velocity_x = 0.0
    @velocity_y = 0.0
    @velocity_z = 0.0
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    if Client.protocol_version >= 777_u32
      position_path = Minecraft::EntityMovement::PositionPath.read(packet)
      yaw = packet.read_float
      pitch = packet.read_float
      on_ground = packet.read_bool
      return self.new(entity_id, position_path, yaw, pitch, on_ground)
    end

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
      if Client.protocol_version >= 777_u32
        (position_path || Minecraft::EntityMovement::PositionPath.new(Vec3d.new(x, y, z))).write(buffer)
        buffer.write_full yaw
        buffer.write_full pitch
        buffer.write on_ground?
        next
      end
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
      entity.position = position_path.try(&.end_position) || Vec3d.new(x, y, z)
      entity.velocity = Vec3d.new(velocity_x, velocity_y, velocity_z) unless Client.protocol_version >= 777_u32
      entity.pitch = pitch
      entity.yaw = yaw
      entity.on_ground = on_ground? if Client.protocol_version >= 777_u32
    end
  end
end
