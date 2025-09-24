require "../packet"

class Rosegold::Serverbound::PlayerLook < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x1F_u8, # MC 1.21.8,
  })

  property \
    yaw : Float32,
    pitch : Float32
  property? \
    on_ground : Bool,
    pushing_against_wall : Bool = false

  def initialize(yaw : Float32, pitch : Float32, @on_ground : Bool, @pushing_against_wall : Bool = false)
    @yaw = sanitize_angle(yaw)
    @pitch = sanitize_angle(pitch)
  end

  def self.new(look : Look, on_ground)
    self.new(look.yaw, look.pitch, on_ground)
  end

  private def sanitize_angle(value : Float32) : Float32
    # Check for NaN or infinite values - replace with 0
    return 0.0_f32 if value.nan? || value.infinite?

    # Normalize angle to valid range (-180 to 180)
    while value > 180.0_f32
      value -= 360.0_f32
    end
    while value < -180.0_f32
      value += 360.0_f32
    end

    value
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write yaw
      buffer.write pitch

      # MC 1.21.4+ format: Use bit field (0x01: on ground, 0x02: pushing against wall)
      flags = 0_u8
      flags |= 0x01_u8 if on_ground?
      flags |= 0x02_u8 if pushing_against_wall?
      buffer.write flags
    end.to_slice
  end
end
