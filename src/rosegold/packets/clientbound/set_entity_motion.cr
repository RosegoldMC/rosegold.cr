class Rosegold::Clientbound::SetEntityMotion < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x5E_u32, # MC 1.21.8
    774_u32 => 0x63_u32, # MC 1.21.11
    775_u32 => 0x65_u32, # MC 26.1
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : UInt64,
    velocity_x : Float64,
    velocity_y : Float64,
    velocity_z : Float64

  def initialize(@entity_id, @velocity_x, @velocity_y, @velocity_z)
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    if Client.protocol_version >= 774_u32
      velocity_x, velocity_y, velocity_z = packet.read_lp_vec3
    else
      velocity_x = packet.read_short.to_f64 / 8000.0
      velocity_y = packet.read_short.to_f64 / 8000.0
      velocity_z = packet.read_short.to_f64 / 8000.0
    end
    self.new(entity_id, velocity_x, velocity_y, velocity_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      if Client.protocol_version >= 774_u32
        buffer.write_lp_vec3(velocity_x, velocity_y, velocity_z)
      else
        buffer.write_full (velocity_x * 8000.0).round.to_i16
        buffer.write_full (velocity_y * 8000.0).round.to_i16
        buffer.write_full (velocity_z * 8000.0).round.to_i16
      end
    end.to_slice
  end

  def callback(client)
    velocity = Vec3d.new(velocity_x, velocity_y, velocity_z)
    if entity_id == client.player.entity_id
      Log.debug { "Received velocity for self: #{velocity_x}, #{velocity_y}, #{velocity_z}" }
      client.physics.pending_velocity = velocity
    elsif entity = client.dimension.entities[entity_id]?
      entity.velocity = velocity
    end
  end
end
