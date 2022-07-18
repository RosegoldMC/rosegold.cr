require "./look"
require "./vec3"

class Rosegold::Player
  property \
    feet : Vec3d = Vec3d::ORIGIN,
    look : LookDeg = LookDeg::SOUTH,
    onGround : Bool = true,
    health : Float32 = 0,
    food : Float32 = 0,
    saturation : Float32 = 0,
    gamemode : UInt8 = 0
end
