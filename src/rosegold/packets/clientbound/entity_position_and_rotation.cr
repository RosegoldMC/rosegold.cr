require "../../../minecraft/entity_movement"

class Rosegold::Clientbound::EntityPositionAndRotation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x2F_u32, # MC 1.21.8
    774_u32 => 0x34_u32, # MC 1.21.11
    773_u32 => 0x34_u32, # MC 1.21.9
    775_u32 => 0x36_u32, # MC 26.1
    776_u32 => 0x36_u32, # MC 26.2
    777_u32 => 0x37_u32,
  })

  property \
    entity_id : UInt64,
    delta_x : Int16,
    delta_y : Int16,
    delta_z : Int16,
    yaw : Float32,
    pitch : Float32

  property? \
    on_ground : Bool

  getter position_delta : Minecraft::EntityMovement::VecDelta?

  def initialize(@entity_id, @delta_x, @delta_y, @delta_z, @yaw, @pitch, @on_ground)
    @position_delta = nil
  end

  def initialize(@entity_id, @position_delta : Minecraft::EntityMovement::VecDelta, @yaw, @pitch, @on_ground)
    @delta_x = position_delta.delta_x
    @delta_y = position_delta.delta_y
    @delta_z = position_delta.delta_z
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    if Client.protocol_version >= 777_u32
      properties = packet.read_var_int
      delta = Minecraft::EntityMovement::VecDelta.read(packet, properties >> 1)
      yaw = packet.read_angle256_deg
      pitch = packet.read_angle256_deg
      return self.new(entity_id, delta, yaw, pitch, (properties & 1) != 0)
    end

    delta_x = packet.read_short
    delta_y = packet.read_short
    delta_z = packet.read_short
    yaw = packet.read_angle256_deg
    pitch = packet.read_angle256_deg
    on_ground = packet.read_bool

    self.new(entity_id, delta_x, delta_y, delta_z, yaw, pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      if Client.protocol_version >= 777_u32
        delta = position_delta || Minecraft::EntityMovement::VecDelta.new(delta_x, delta_y, delta_z)
        buffer.write (delta.step_count << 1) | (on_ground? ? 1_u32 : 0_u32)
        delta.write(buffer)
        buffer.write_angle256_deg yaw
        buffer.write_angle256_deg pitch
        next
      end
      buffer.write delta_x
      buffer.write delta_y
      buffer.write delta_z
      buffer.write_angle256_deg yaw
      buffer.write_angle256_deg pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity position and rotation packet for entity ID #{entity_id}, delta X #{delta_x}, delta Y #{delta_y}, delta Z #{delta_z}, yaw #{yaw}, pitch #{pitch}" }
    entity = client.dimension.entities[entity_id]?

    if entity.nil?
      Log.warn { "Received entity position and rotation packet for unknown entity ID #{entity_id}" }
      return
    end

    if delta = position_delta
      entity.position = delta.resolve_position(entity.position)
    else
      entity.position = entity.position.plus(delta_x / 128.0 / 32.0, delta_y / 128.0 / 32.0, delta_z / 128.0 / 32.0)
      entity.velocity = Vec3d.new(delta_x / 128.0 / 32.0, delta_y / 128.0 / 32.0, delta_z / 128.0 / 32.0)
    end
    entity.yaw = yaw
    entity.pitch = pitch
    entity.on_ground = on_ground?
  end
end
