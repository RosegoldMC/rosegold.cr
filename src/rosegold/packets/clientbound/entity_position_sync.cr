require "../packet"

class Rosegold::Clientbound::EntityPositionSync < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x1F_u8, # MC 1.21.8,
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

  def initialize(@entity_id, @x, @y, @z, @velocity_x, @velocity_y, @velocity_z, @yaw, @pitch, @on_ground)
  end

  def self.read(packet)
    entity_id = packet.read_var_long
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    velocity_x = packet.read_double
    velocity_y = packet.read_double
    velocity_z = packet.read_double
    yaw = packet.read_angle256_deg
    pitch = packet.read_angle256_deg
    on_ground = packet.read_bool

    self.new(entity_id, x, y, z, velocity_x, velocity_y, velocity_z, yaw, pitch, on_ground)
  end

  # Custom VarLong encoding to work around minecraft IO bug
  private def write_var_long(buffer, value : UInt64)
    more = true
    while more
      b = (value & 0x7F).to_u8
      value >>= 7
      if value == 0
        more = false
      else
        b |= 0x80
      end
      buffer.write_byte(b)
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      # Use custom VarLong encoding for entity_id
      write_var_long(buffer, entity_id)

      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write velocity_x
      buffer.write velocity_y
      buffer.write velocity_z
      buffer.write yaw
      buffer.write pitch
      buffer.write on_ground?
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity position sync for entity ID #{entity_id}: (#{x}, #{y}, #{z})" }
    if entity = client.dimension.entities[entity_id]?
      entity.position = Vec3d.new(x, y, z)
      entity.velocity = Vec3d.new(velocity_x, velocity_y, velocity_z)
      entity.pitch = pitch
      entity.yaw = yaw
    end
  end
end
