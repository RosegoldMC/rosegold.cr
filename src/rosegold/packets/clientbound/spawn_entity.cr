class Rosegold::Clientbound::SpawnEntity < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x01_u32, # MC 1.21.8
    774_u32 => 0x01_u32, # MC 1.21.11
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : UInt64,
    uuid : UUID,
    entity_type : UInt32,
    x : Float64,
    y : Float64,
    z : Float64,
    pitch : Float64,
    yaw : Float64,
    head_yaw : Float64,
    data : UInt32 = 0_u32, # Default to 0 for compatibility
    velocity_x : Float64,
    velocity_y : Float64,
    velocity_z : Float64

  def initialize(@entity_id, @uuid, @entity_type, @x, @y, @z, @pitch, @yaw, @head_yaw, @data, @velocity_x, @velocity_y, @velocity_z)
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    uuid = packet.read_uuid
    entity_type = packet.read_var_int
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double

    if Client.protocol_version >= 774_u32
      # 1.21.11+: velocity as LpVec3, before angles
      velocity_x, velocity_y, velocity_z = packet.read_lp_vec3
      pitch = packet.read_angle256_deg
      yaw = packet.read_angle256_deg
      head_yaw = packet.read_angle256_deg
      data = packet.read_var_int
    else
      # 1.21.8: angles before velocity (3 x Int16)
      pitch = packet.read_angle256_deg
      yaw = packet.read_angle256_deg
      head_yaw = packet.read_angle256_deg
      data = packet.read_var_int
      velocity_x = packet.read_short.to_f64 / 8000.0
      velocity_y = packet.read_short.to_f64 / 8000.0
      velocity_z = packet.read_short.to_f64 / 8000.0
    end

    self.new(entity_id, uuid, entity_type, x, y, z, pitch, yaw, head_yaw, data, velocity_x, velocity_y, velocity_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      buffer.write entity_id.to_u32
      buffer.write uuid
      buffer.write entity_type
      buffer.write_full x
      buffer.write_full y
      buffer.write_full z

      if Client.protocol_version >= 774_u32
        buffer.write_lp_vec3(velocity_x, velocity_y, velocity_z)
        buffer.write_angle256_deg pitch
        buffer.write_angle256_deg yaw
        buffer.write_angle256_deg head_yaw
        buffer.write data
      else
        buffer.write_angle256_deg pitch
        buffer.write_angle256_deg yaw
        buffer.write_angle256_deg head_yaw
        buffer.write data
        buffer.write_full (velocity_x * 8000.0).round.to_i16
        buffer.write_full (velocity_y * 8000.0).round.to_i16
        buffer.write_full (velocity_z * 8000.0).round.to_i16
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received spawn entity packet for entity ID #{entity_id}, UUID #{uuid}, type #{entity_type}" }
    client.dimension.entities[entity_id] = Rosegold::Entity.new \
      entity_id.to_u32,
      uuid,
      entity_type,
      Vec3d.new(x, y, z),
      pitch.to_f32,
      yaw.to_f32,
      head_yaw.to_f32,
      Vec3d.new(velocity_x, velocity_y, velocity_z),
      living: true
  end

  ENTITY_TYPE_PLAYER_BY_PROTOCOL = {
    772_u32 => 149_u32, # MC 1.21.8
    774_u32 => 155_u32, # MC 1.21.11
  }

  def self.entity_type_player : UInt32
    ENTITY_TYPE_PLAYER_BY_PROTOCOL[Client.protocol_version]? || 155_u32
  end
end
