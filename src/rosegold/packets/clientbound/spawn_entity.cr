class Rosegold::Clientbound::SpawnEntity < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x01_u8, # MC 1.21.8,
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : UInt32,
    uuid : UUID,
    entity_type : UInt32,
    x : Float64,
    y : Float64,
    z : Float64,
    pitch : Float64,
    yaw : Float64,
    head_yaw : Float64,
    data : UInt32 = 0_u32, # Default to 0 for compatibility
    velocity_x : Int16,
    velocity_y : Int16,
    velocity_z : Int16

  def initialize(@entity_id, @uuid, @entity_type, @x, @y, @z, @pitch, @yaw, @head_yaw, @data, @velocity_x, @velocity_y, @velocity_z)
  end

  def self.read(packet)
    entity_id = packet.read_var_int
    uuid = packet.read_uuid
    entity_type = packet.read_var_int
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    pitch = packet.read_angle256_deg
    yaw = packet.read_angle256_deg
    head_yaw = packet.read_angle256_deg
    data = packet.read_var_int # Data field is required according to protocol docs
    velocity_x = packet.read_short
    velocity_y = packet.read_short
    velocity_z = packet.read_short

    self.new(entity_id, uuid, entity_type, x, y, z, pitch, yaw, head_yaw, data, velocity_x, velocity_y, velocity_z)
  end

  # Custom VarLong encoding to work around minecraft IO bug
  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      buffer.write entity_id
      buffer.write uuid
      buffer.write entity_type
      buffer.write_full x
      buffer.write_full y
      buffer.write_full z
      buffer.write_angle256_deg pitch
      buffer.write_angle256_deg yaw
      buffer.write_angle256_deg head_yaw
      buffer.write data
      buffer.write_full velocity_x
      buffer.write_full velocity_y
      buffer.write_full velocity_z
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received spawn entity packet for entity ID #{entity_id}, UUID #{uuid}, type #{entity_type}" }
    client.dimension.entities[entity_id] = Rosegold::Entity.new \
      entity_id,
      uuid,
      entity_type,
      Vec3d.new(x, y, z),
      pitch.to_f32,
      yaw.to_f32,
      head_yaw.to_f32,
      Vec3d.new(velocity_x, velocity_y, velocity_z),
      living: true
  end

  # Entity type constants (matching vanilla Minecraft)
  ENTITY_TYPE_PLAYER = 149_u32 # Player entity type ID in MC 1.21.8
end
