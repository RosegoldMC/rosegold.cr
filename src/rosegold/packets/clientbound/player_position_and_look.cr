require "../../look"
require "../../vec3"

# flags: x/y/z/yaw/pitch. If a flag is set, its value is relative to the current player position/look.
class Rosegold::Clientbound::PlayerPositionAndLook < Rosegold::Clientbound::Packet
  property \
    x_raw : Float64,
    y_raw : Float64,
    z_raw : Float64,
    yaw_deg_raw : Float32,
    pitch_deg_raw : Float32,
    flags : UInt8,
    teleport_id : UInt32,
    dismount_vehicle : Bool

  def initialize(
    @x_raw,
    @y_raw,
    @z_raw,
    @yaw_deg_raw,
    @pitch_deg_raw,
    @flags,
    @teleport_id,
    @dismount_vehicle
  )
  end

  def self.read(packet)
    self.new(
      packet.read_float64,
      packet.read_float64,
      packet.read_float64,
      packet.read_float32,
      packet.read_float32,
      packet.read_byte,
      packet.read_var_int,
      packet.read_bool
    )
  end

  def feet_vec(reference : Vec3d)
    Vec3d.new(
      flags & 0b001 ? reference.x + x_raw : x_raw,
      flags & 0b010 ? reference.y + y_raw : y_raw,
      flags & 0b100 ? reference.z + z_raw : z_raw)
  end

  def look_rad(reference_rad : LookRad)
    look_deg(reference_rad.to_deg).to_rad
  end

  def look_deg(reference_deg : LookDeg)
    LookDeg.new(
      flags & 0b1000 ? reference_deg.yaw + yaw_deg_raw : yaw_deg_raw,
      flags & 0b10000 ? reference_deg.pitch + pitch_deg_raw : pitch_deg_raw)
  end

  def callback(client)
    client.send_packet Rosegold::Serverbound::TeleportConfirm.new teleport_id

    # TODO: set client feet/look
    # TODO: close the “Downloading Terrain” screen when joining/respawning
  end
end
