require "../../world/player_list"
require "../packet"

class Rosegold::Clientbound::SpawnPlayer < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x04_u8

  property \
    entity_id : UInt64,
    uuid : UUID,
    location : Vec3d,
    look : Look

  property players : Array(PlayerList::Entry)

  def initialize(@entity_id, @uuid, @location, @look, @players = Array(PlayerList::Entry).new); end

  def self.read(packet)
    entity_id = packet.read_var_long
    uuid = packet.read_uuid
    location = Vec3d.new(packet.read_double, packet.read_double, packet.read_double)
    look = Look.new(yaw: packet.read_angle256_deg, pitch: packet.read_angle256_deg)

    self.new(entity_id, uuid, location, look)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write uuid
      buffer.write location.x
      buffer.write location.y
      buffer.write location.z
      buffer.write_angle256_deg look.yaw
      buffer.write_angle256_deg look.pitch
    end.to_slice
  end

  def get_name_by_uuid(uuid)
    players.each do |player|
      if player.name && player.uuid == uuid
        return player.name
      end
    end
    nil
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
      Log.info { "[RADAR] #{get_name_by_uuid(uuid)} appeared at [#{location.x}, #{location.z}]" }
  end
end
