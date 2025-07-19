require "../packet"

class Rosegold::Clientbound::SpawnPlayer < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x04_u8, # MC 1.18
    767_u32 => 0x02_u8, # MC 1.21
    771_u32 => 0x02_u8, # MC 1.21.6
  })

  property \
    entity_id : UInt64,
    uuid : UUID,
    location : Vec3d,
    look : Look

  def initialize(@entity_id, @uuid, @location, @look); end

  def self.read(packet)
    entity_id = packet.read_var_long
    uuid = packet.read_uuid
    location = Vec3d.new(packet.read_double, packet.read_double, packet.read_double)
    look = Look.new(yaw: packet.read_angle256_deg, pitch: packet.read_angle256_deg)

    self.new(entity_id, uuid, location, look)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write uuid
      buffer.write location.x
      buffer.write location.y
      buffer.write location.z
      buffer.write_angle256_deg look.yaw
      buffer.write_angle256_deg look.pitch
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received spawn player packet for entity ID #{entity_id}, UUID #{uuid}" }

    client.dimension.entities[entity_id] = Rosegold::Entity.new(
      entity_id,
      uuid,
      111_u32,
      location,
      look.pitch,
      look.yaw,
      0_u8,
      Vec3d.new(0, 0, 0))
  end
end
