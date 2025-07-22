class Rosegold::Clientbound::SpawnLivingEntity < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x02_u8, # MC 1.18
    767_u32 => 0x01_u8, # MC 1.21
    769_u32 => 0x01_u8, # MC 1.21.4,
    771_u32 => 0x01_u8, # MC 1.21.6,
    772_u32 => 0x01_u8, # MC 1.21.8,
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : UInt64,
    uuid : UUID,
    entity_type : UInt32,
    x : Float64,
    y : Float64,
    z : Float64,
    pitch : Float32,
    yaw : Float32,
    head_yaw : Float32,
    data : UInt32 = 0_u32, # Default to 0 for compatibility
    velocity_x : Int16,
    velocity_y : Int16,
    velocity_z : Int16

  def initialize(@entity_id, @uuid, @entity_type, @x, @y, @z, @pitch, @yaw, @head_yaw, @data, @velocity_x, @velocity_y, @velocity_z)
  end

  def self.read(packet)
    entity_id = packet.read_var_long
    uuid = packet.read_uuid
    entity_type = packet.read_var_int
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    pitch = packet.read_angle256_deg
    yaw = packet.read_angle256_deg
    head_yaw = packet.read_angle256_deg
    if Client.protocol_version >= 767
      data = packet.read_var_int # Read data field for MC 1.21+
    else
      data = 0_u32 # Default to 0 for older versions
    end
    velocity_x = packet.read_short
    velocity_y = packet.read_short
    velocity_z = packet.read_short

    self.new(entity_id, uuid, entity_type, x, y, z, pitch, yaw, head_yaw, data, velocity_x, velocity_y, velocity_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write uuid
      buffer.write entity_type
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write pitch
      buffer.write yaw
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received spawn entity packet for entity ID #{entity_id}, UUID #{uuid}, type #{entity_type}" }
    client.dimension.entities[entity_id] = Rosegold::Entity.new \
      entity_id,
      uuid,
      entity_type,
      Vec3d.new(x, y, z),
      pitch,
      yaw,
      head_yaw,
      Vec3d.new(velocity_x, velocity_y, velocity_z),
      living: true
  end
end
