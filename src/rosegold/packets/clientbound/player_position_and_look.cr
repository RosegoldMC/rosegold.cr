require "../../world/look"
require "../../world/vec3"
require "../packet"

# relative_flags: x/y/z/yaw/pitch. If a flag is set, its value is relative to the current player position/look.
class Rosegold::Clientbound::PlayerPositionAndLook < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x38_u8

  property \
    x_raw : Float64,
    y_raw : Float64,
    z_raw : Float64,
    yaw_deg_raw : Float32,
    pitch_deg_raw : Float32,
    relative_flags : UInt8,
    teleport_id : UInt32
  property? \
    dismount_vehicle : Bool

  def initialize(
    @x_raw,
    @y_raw,
    @z_raw,
    @yaw_deg_raw,
    @pitch_deg_raw,
    @relative_flags,
    @teleport_id,
    @dismount_vehicle
  ); end

  def self.new(location : Vec3d, look : Look, teleport_id : UInt32, dismount_vehicle = false)
    self.new(
      location.x, location.y, location.z,
      look.yaw_deg, look.pitch_deg,
      0,
      teleport_id,
      dismount_vehicle,
    )
  end

  def self.read(packet)
    self.new(
      packet.read_double,
      packet.read_double,
      packet.read_double,
      packet.read_float,
      packet.read_float,
      packet.read_byte,
      packet.read_var_int,
      packet.read_bool
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write x_raw
      buffer.write y_raw
      buffer.write z_raw
      buffer.write yaw_deg_raw
      buffer.write pitch_deg_raw
      buffer.write relative_flags
      buffer.write teleport_id
      buffer.write dismount_vehicle?
    end.to_slice
  end

  def feet(reference : Vec3d)
    Vec3d.new(
      relative_flags.bits_set?(0b001) ? reference.x + x_raw : x_raw,
      relative_flags.bits_set?(0b010) ? reference.y + y_raw : y_raw,
      relative_flags.bits_set?(0b100) ? reference.z + z_raw : z_raw)
  end

  def look(reference : Look)
    Look.from_deg(
      relative_flags.bits_set?(0b1000) ? reference.yaw_deg + yaw_deg_raw : yaw_deg_raw,
      relative_flags.bits_set?(0b10000) ? reference.pitch_deg + pitch_deg_raw : pitch_deg_raw)
  end

  def callback(client)
    player = client.player
    player.feet = feet player.feet
    player.look = look player.look
    player.velocity = Vec3d::ORIGIN

    client.queue_packet Serverbound::TeleportConfirm.new teleport_id

    Log.debug { "Position reset: #{player.feet} #{player.look} dismount=#{dismount_vehicle?} flags=#{relative_flags}" }

    client.physics.start

    client.physics.reset

    # TODO: close the “Downloading Terrain” screen when joining/respawning
  end
end
