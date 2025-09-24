require "../packet"

class Rosegold::Clientbound::PlayerAbilities < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x39_u8, # MC 1.21.8,
  })

  property \
    flags : UInt8,
    flying_speed : Float32,
    field_of_view_modifier : Float32

  def initialize(@flags, @flying_speed, @field_of_view_modifier); end

  def self.read(packet)
    self.new(
      packet.read_byte,
      packet.read_float,
      packet.read_float
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write flags
      buffer.write flying_speed
      buffer.write field_of_view_modifier
    end.to_slice
  end

  def callback(client)
    Log.debug { "Player abilities updated: flags=0x#{flags.to_s(16).upcase.rjust(2, '0')}, flying_speed=#{flying_speed}, fov_modifier=#{field_of_view_modifier}" }

    # Update client player abilities based on flags
    client.player.invulnerable = (flags & 0x01) != 0
    client.player.flying = (flags & 0x02) != 0
    client.player.allow_flying = (flags & 0x04) != 0
    client.player.creative_mode = (flags & 0x08) != 0
    client.player.flying_speed = flying_speed
    client.player.field_of_view_modifier = field_of_view_modifier
  end

  # Convenience methods for checking individual flags
  def invulnerable?
    (flags & 0x01) != 0
  end

  def flying?
    (flags & 0x02) != 0
  end

  def allow_flying?
    (flags & 0x04) != 0
  end

  def creative_mode?
    (flags & 0x08) != 0
  end
end
