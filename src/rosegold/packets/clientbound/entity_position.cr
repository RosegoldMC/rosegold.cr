class Rosegold::Clientbound::EntityPosition < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x29_u8

  property \
    entity_id : UInt32,
    delta_x : Int16,
    delta_y : Int16,
    delta_z : Int16

  property? \
    on_ground : Bool

  def initialize(@entity_id, @delta_x, @delta_y, @delta_z, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_int
    delta_x = packet.read_short
    delta_y = packet.read_short
    delta_z = packet.read_short
    on_ground = packet.read_bool

    self.new(entity_id, delta_x, delta_y, delta_z, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write delta_x
      buffer.write delta_y
      buffer.write delta_z
      buffer.write on_ground
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity position packet for entity ID #{entity_id}, delta X #{delta_x}, delta Y #{delta_y}, delta Z #{delta_z}" }
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity position packet for unknown entity ID #{entity_id}" }
      return
    end

    new_pos = entity.position.plus(delta_x / 128.0 / 32.0, delta_y / 128.0 / 32.0, delta_z / 128.0 / 32.0)

    entity.position = new_pos
  end
end
