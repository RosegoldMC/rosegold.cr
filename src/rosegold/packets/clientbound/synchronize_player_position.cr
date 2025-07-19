# MC 1.21+ replacement for PlayerPositionAndLook packet
require "../../world/look"
require "../../world/vec3"
require "../packet"

# relative_flags: x/y/z/yaw/pitch. If a flag is set, its value is relative to the current player position/look.
class Rosegold::Clientbound::SynchronizePlayerPosition < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (MC 1.21+ replacement for PlayerPositionAndLook)
  packet_ids({
    767_u32 => 0x40_u8, # MC 1.21
    771_u32 => 0x40_u8, # MC 1.21.6
  })

  property \
    x_raw : Float64,
    y_raw : Float64,
    z_raw : Float64,
    yaw_raw : Float32,
    pitch_raw : Float32,
    relative_flags : UInt8,
    teleport_id : UInt32

  def initialize(@x_raw, @y_raw, @z_raw, @yaw_raw, @pitch_raw, @relative_flags, @teleport_id, @dismount_vehicle = false)
  end

  def self.read(packet)
    x = packet.read_double
    y = packet.read_double
    z = packet.read_double
    yaw = packet.read_float
    pitch = packet.read_float
    relative_flags = packet.read_byte
    teleport_id = packet.read_var_int

    self.new(x, y, z, yaw, pitch, relative_flags, teleport_id)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write x_raw
      io.write y_raw
      io.write z_raw
      io.write yaw_raw
      io.write pitch_raw
      io.write relative_flags
      io.write teleport_id
    end.to_slice
  end

  def feet(previous_feet : Vec3d) : Vec3d
    x = x_raw
    y = y_raw
    z = z_raw

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
    player.velocity = Vec3d::ORIGIN

    client.queue_packet Serverbound::TeleportConfirm.new teleport_id

    Log.debug { "Position synchronized: #{player.feet} #{player.look} flags=#{relative_flags}" }

    client.physics.handle_reset # This unpauses physics!
  end
end
