class Rosegold::Clientbound::SpawnEntity < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    758_u32 => 0x00_u8, # MC 1.18
    767_u32 => 0x01_u8, # MC 1.21
    771_u32 => 0x01_u8, # MC 1.21.6
  })

  property \
    entity_id : UInt64,
    uuid : UUID,
    entity_type : UInt32,
    x : Float64,
    y : Float64,
    z : Float64,
    pitch : Float32,
    yaw : Float32,
    data : UInt32,
    velocity_x : Int16,
    velocity_y : Int16,
    velocity_z : Int16

  def initialize(@entity_id, @uuid, @entity_type, @x, @y, @z, @pitch, @yaw, @data, @velocity_x, @velocity_y, @velocity_z)
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
    data = packet.read_var_int
    velocity_x = packet.read_short
    velocity_y = packet.read_short
    velocity_z = packet.read_short

    self.new(entity_id, uuid, entity_type, x, y, z, pitch, yaw, data, velocity_x, velocity_y, velocity_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write uuid
      buffer.write entity_type
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write pitch
      buffer.write yaw
      buffer.write data
      buffer.write velocity_x
      buffer.write velocity_y
      buffer.write velocity_z
    end.to_slice
  end

  def callback(client)
    client.dimension.entities[entity_id] = Rosegold::Entity.new \
      entity_id,
      uuid,
      entity_type,
      Vec3d.new(x, y, z),
      pitch,
      yaw,
      yaw,
      Vec3d.new(velocity_x, velocity_y, velocity_z)
  end
end
