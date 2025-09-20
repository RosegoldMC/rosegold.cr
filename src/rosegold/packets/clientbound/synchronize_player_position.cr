# MC 1.21+ replacement for PlayerPositionAndLook packet
require "../../world/look"
require "../../world/vec3"
require "../packet"
require "../../events/player_position_update"

# relative_flags: x/y/z/yaw/pitch. If a flag is set, its value is relative to the current player position/look.
class Rosegold::Clientbound::SynchronizePlayerPosition < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (MC 1.21+ replacement for PlayerPositionAndLook)
  packet_ids({
    772_u32 => 0x41_u8, # MC 1.21.8,
  })

  property \
    x_raw : Float64,
    y_raw : Float64,
    z_raw : Float64,
    yaw_raw : Float32,
    pitch_raw : Float32,
    relative_flags : UInt8,
    teleport_id : UInt32

  # MC 1.21.6+ additional velocity fields
  property \
    velocity_x : Float64 = 0.0,
    velocity_y : Float64 = 0.0,
    velocity_z : Float64 = 0.0

  property? dismount_vehicle : Bool = false

  def initialize(@x_raw, @y_raw, @z_raw, @yaw_raw, @pitch_raw, @relative_flags, @teleport_id, @dismount_vehicle = false, @velocity_x = 0.0, @velocity_y = 0.0, @velocity_z = 0.0)
  end

  def self.read(packet)
    # MC 1.21.6+ format: Teleport ID first, then coordinates, velocities, angles, flags
    teleport_id = packet.read_var_int
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    velocity_x = packet.read_double
    velocity_y = packet.read_double
    velocity_z = packet.read_double
    yaw = packet.read_float
    pitch = packet.read_float
    relative_flags = packet.read_byte

    # Read dismount vehicle flag (MC 1.21.6+)
    dismount_vehicle = packet.read_byte != 0_u8

    # Read remaining bytes - appears to be 2 additional bytes in MC 1.21.8
    extra_byte1 = packet.read_byte
    extra_byte2 = packet.read_byte
    Log.debug { "SynchronizePlayerPosition extra bytes: #{extra_byte1.to_s(16)} #{extra_byte2.to_s(16)}" }

    self.new(x, y, z, yaw, pitch, relative_flags, teleport_id, dismount_vehicle, velocity_x, velocity_y, velocity_z)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)

      # MC 1.21.6+ format: Teleport ID first, then coordinates, velocities, angles, flags
      io.write teleport_id
      io.write x_raw
      io.write y_raw
      io.write z_raw
      io.write velocity_x
      io.write velocity_y
      io.write velocity_z
      io.write yaw_raw
      io.write pitch_raw
      io.write relative_flags
      io.write(dismount_vehicle? ? 1_u8 : 0_u8)
      io.write 0_u8 # Extra byte 1 (value 0)
      io.write 0_u8 # Extra byte 2 (value 0)
    end.to_slice
  end

  def feet(previous_feet : Vec3d) : Vec3d
    x = sanitize_coordinate(x_raw, -30_000_000.0, 30_000_000.0)
    y = sanitize_coordinate(y_raw, -20_000_000.0, 20_000_000.0)
    z = sanitize_coordinate(z_raw, -30_000_000.0, 30_000_000.0)

    if relative_flags & 0x01 != 0
      x += previous_feet.x
    end
    if relative_flags & 0x02 != 0
      y += previous_feet.y
    end
    if relative_flags & 0x04 != 0
      z += previous_feet.z
    end

    Vec3d.new x, y, z
  end

  private def sanitize_coordinate(value : Float64, min : Float64, max : Float64) : Float64
    # Check for NaN or infinite values - replace with 0
    return 0.0 if value.nan? || value.infinite?

    # Check for extremely small values that might be corrupted (near-zero scientific notation)
    return 0.0 if value.abs < 1e-100

    # Clamp to valid ranges as per protocol specification
    value.clamp(min, max)
  end

  def look(previous_look : Look) : Look
    yaw = yaw_raw
    pitch = pitch_raw

    if relative_flags & 0x08 != 0
      yaw += previous_look.yaw
    end
    if relative_flags & 0x10 != 0
      pitch += previous_look.pitch
    end

    Look.new yaw, pitch
  end

  def callback(client)
    player = client.player
    player.feet = feet player.feet
    player.look = look player.look

    # Set velocity from packet for MC 1.21.6+
    player.velocity = Vec3d.new(velocity_x, velocity_y, velocity_z)

    client.queue_packet Serverbound::TeleportConfirm.new teleport_id

    # Emit player position update event
    client.emit_event Event::PlayerPositionUpdate.new(player.feet, player.look)

    Log.debug { "Position synchronized: #{player.feet} #{player.look} flags=#{relative_flags}" }

    client.physics.handle_reset # This unpauses physics!
  end
end
