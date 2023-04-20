class Rosegold::Clientbound::EntityRotation < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x2B_u8

  property \
    entity_id : UInt32,
    yaw : Float32,
    pitch : Float32

  property? \
    on_ground : Bool

  def initialize(@entity_id, @yaw, @pitch, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_int
    yaw = packet.read_angle256_deg
    pitch = packet.read_angle256_deg
    on_ground = packet.read_bool

    self.new(entity_id, yaw, pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write yaw
      buffer.write pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity rotation packet for entity ID #{entity_id}, yaw #{yaw}, pitch #{pitch}" }
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity rotation packet for unknown entity ID #{entity_id}" }
      return
    end

    entity.yaw = yaw
    entity.pitch = pitch
    entity.on_ground = on_ground?
  end
end
