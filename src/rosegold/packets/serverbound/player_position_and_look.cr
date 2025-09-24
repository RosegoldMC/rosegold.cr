require "../../world/look"
require "../../world/vec3"
require "../packet"

class Rosegold::Serverbound::PlayerPositionAndLook < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x1E_u8, # MC 1.21.8,
  })

  property \
    feet : Vec3d,
    look : Look
  property? \
    on_ground : Bool,
    pushing_against_wall : Bool = false

  def initialize(feet : Vec3d, look : Look, @on_ground : Bool, @pushing_against_wall : Bool = false)
    # Validate and sanitize coordinates
    @feet = Vec3d.new(
      sanitize_coordinate(feet.x, -30_000_000.0, 30_000_000.0),
      sanitize_coordinate(feet.y, -20_000_000.0, 20_000_000.0),
      sanitize_coordinate(feet.z, -30_000_000.0, 30_000_000.0)
    )

    # Validate and sanitize look angles
    @look = Look.new(
      sanitize_angle(look.yaw),
      sanitize_angle(look.pitch)
    )
  end

  def self.read(packet)
    feet = Vec3d.new(
      packet.read_double,
      packet.read_double,
      packet.read_double
    )
    look = Look.new(
      packet.read_float,
      packet.read_float
    )

    # MC 1.21.8 (protocol 772) format: Read bit field (0x01: on ground, 0x02: pushing against wall)
    flags = packet.read_byte
    on_ground = (flags & 0x01_u8) != 0
    pushing_against_wall = (flags & 0x02_u8) != 0

    self.new(feet, look, on_ground, pushing_against_wall)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write feet.x
      buffer.write feet.y
      buffer.write feet.z
      buffer.write look.yaw
      buffer.write look.pitch

      # MC 1.21.8 (protocol 772) format: Use bit field (0x01: on ground, 0x02: pushing against wall)
      flags = 0_u8
      flags |= 0x01_u8 if on_ground?
      flags |= 0x02_u8 if pushing_against_wall?
      buffer.write flags
    end.to_slice
  end

  private def sanitize_coordinate(value : Float64, min : Float64, max : Float64) : Float64
    # Check for NaN or infinite values - replace with 0
    return 0.0 if value.nan? || value.infinite?

    # Check for extremely small values that might be corrupted (near-zero scientific notation)
    return 0.0 if value.abs < 1e-100

    # Clamp to valid ranges as per protocol specification
    value.clamp(min, max)
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
end
