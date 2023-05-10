require "./look"
require "./vec3"

# Holds assumed server-side player state.
# Only gets updated when reading/writing packets.
class Rosegold::Player
  DEFAULT_AABB  = AABBf.new -0.3, 0.0, -0.3, 0.3, 1.8, 0.3
  SNEAKING_AABB = AABBf.new -0.3, 0.0, -0.3, 0.3, 1.5, 0.3
  CRAWLING_AABB = AABBf.new -0.3, 0.0, -0.3, 0.3, 0.625, 0.3

  DEFAULT_EYE_HEIGHT  = 1.62
  SNEAKING_EYE_HEIGHT = 1.27
  CRAWLING_EYE_HEIGHT = 0.40

  property \
    uuid : UUID?,
    username : String?, # Note: The server may give us a different name than we used during authentication.
    entity_id : Int32 = 0,
    look : Look = Look::SOUTH,
    feet : Vec3d = Vec3d::ORIGIN,
    velocity : Vec3d = Vec3d::ORIGIN,
    health : Float32 = 0,
    food : UInt32 = 0,
    saturation : Float32 = 0,
    hotbar_selection : UInt8 = 0,
    gamemode : Int8 = 0,
    time : MCTime = MCTime::UNKNOWN
  property? \
    on_ground : Bool = false,
    sneaking : Bool = false,
    sprinting : Bool = false,
    in_water : Bool = false

  def aabb
    # TODO crawling
    return SNEAKING_AABB + feet if sneaking?
    DEFAULT_AABB + feet
  end

  def eyes
    # TODO crawling
    return feet.up SNEAKING_EYE_HEIGHT if sneaking?
    feet.up DEFAULT_EYE_HEIGHT
  end
end

enum Rosegold::Hand
  MainHand; OffHand
end
