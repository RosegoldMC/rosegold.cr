require "./look"
require "./vec3"

class Rosegold::Player
  PLAYER_AABB = AABBf.new -0.3, 0, -0.3, 0.3, 1.8, 0.3

  property \
    feet : Vec3d = Vec3d::ORIGIN,
    look : LookDeg = LookDeg::SOUTH,
    on_ground : Bool = true,
    health : Float32 = 0,
    food : Float32 = 0,
    saturation : Float32 = 0,
    gamemode : UInt8 = 0

  def aabb
    PLAYER_AABB + feet
  end
end
