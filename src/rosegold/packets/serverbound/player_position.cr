require "../packet"

class Rosegold::Serverbound::PlayerPosition < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (changes between versions!)
  packet_ids({
    758_u32 => 0x11_u8, # MC 1.18
    767_u32 => 0x1C_u8, # MC 1.21 - CHANGED!
    769_u32 => 0x1C_u8, # MC 1.21.4,
    771_u32 => 0x1D_u8, # MC 1.21.6,
  })

  property \
    x : Float64,
    y : Float64,
    z : Float64
  property? \
    on_ground : Bool,
    pushing_against_wall : Bool = false

  def initialize(x : Float64, y : Float64, z : Float64, @on_ground : Bool, @pushing_against_wall : Bool = false)
    # Validate and clamp coordinates according to protocol specification
    @x = sanitize_coordinate(x, -30_000_000.0, 30_000_000.0)
    @y = sanitize_coordinate(y, -20_000_000.0, 20_000_000.0)
    @z = sanitize_coordinate(z, -30_000_000.0, 30_000_000.0)
  end

  def self.new(feet : Vec3d, on_ground)
    self.new(feet.x, feet.y, feet.z, on_ground)
  end

  private def sanitize_coordinate(value : Float64, min : Float64, max : Float64) : Float64
    # Check for NaN or infinite values - replace with 0
    return 0.0 if value.nan? || value.infinite?

    # Check for extremely small values that might be corrupted (near-zero scientific notation)
    return 0.0 if value.abs < 1e-100

    # Clamp to valid ranges as per protocol specification
    value.clamp(min, max)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write x
      buffer.write y
      buffer.write z

      if Client.protocol_version >= 769_u32
        # MC 1.21.4+ format: Use bit field (0x01: on ground, 0x02: pushing against wall)
        flags = 0_u8
        flags |= 0x01_u8 if on_ground?
        flags |= 0x02_u8 if pushing_against_wall?
        buffer.write flags
      else
        # Older formats: Just boolean on_ground
        buffer.write on_ground?
      end
    end.to_slice
  end
end
