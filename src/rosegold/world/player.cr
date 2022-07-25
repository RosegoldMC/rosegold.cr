require "./look"
require "./vec3"

# Holds assumed server-side player state.
# Only gets updated when reading/writing packets.
class Rosegold::Player
  PLAYER_AABB = AABBf.new -0.3, 0.0, -0.3, 0.3, 1.8, 0.3

  property \
    on_ground : Bool = false,
    look : LookDeg = LookDeg::SOUTH,
    feet : Vec3d = Vec3d::ORIGIN,
    velocity : Vec3d = Vec3d::ORIGIN,
    health : Float32 = 0,
    food : Float32 = 0,
    saturation : Float32 = 0,
    gamemode : UInt8 = 0

  def aabb
    PLAYER_AABB + feet
  end

  def eyes
    feet.up 1.625
  end

  def pitch=(pitch)
    look.pitch = pitch
  end

  def yaw=(yaw)
    look.yaw = yaw
  end

  delegate pitch, to: look
  delegate yaw, to: look
end
