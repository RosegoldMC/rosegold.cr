require "./look"
require "./vec3"

class Rosegold::Player
  DEFAULT_AABB  = AABBf.new -0.3, 0.0, -0.3, 0.3, 1.8, 0.3
  SNEAKING_AABB = AABBf.new -0.3, 0.0, -0.3, 0.3, 1.5, 0.3
  CRAWLING_AABB = AABBf.new -0.3, 0.0, -0.3, 0.3, 0.625, 0.3

  DEFAULT_EYE_HEIGHT  = 1.62
  SNEAKING_EYE_HEIGHT = 1.27
  CRAWLING_EYE_HEIGHT = 0.40

  @mutex = Mutex.new

  @feet : Vec3d = Vec3d::ORIGIN
  @velocity : Vec3d = Vec3d::ORIGIN
  @look : Look = Look::SOUTH

  property \
    uuid : UUID?,
    username : String?, # Note: The server may give us a different name than we used during authentication.
    entity_id : UInt64 = 0,
    health : Float32 = 0,
    food : UInt32 = 0,
    saturation : Float32 = 0,
    hotbar_selection : UInt32 = 0,
    gamemode : Int8 = 0,
    effects : Array(EntityEffect) = [] of EntityEffect,
    flying_speed : Float32 = 0.05_f32,
    field_of_view_modifier : Float32 = 0.1_f32
  property? \
    on_ground : Bool = false,
    sneaking : Bool = false,
    sprinting : Bool = false,
    in_water : Bool = false,
    invulnerable : Bool = false,
    flying : Bool = false,
    allow_flying : Bool = false,
    creative_mode : Bool = false

  def feet
    @mutex.synchronize { @feet }
  end

  def feet=(value : Vec3d)
    @mutex.synchronize { @feet = value }
  end

  def velocity
    @mutex.synchronize { @velocity }
  end

  def velocity=(value : Vec3d)
    @mutex.synchronize { @velocity = value }
  end

  def look
    @mutex.synchronize { @look }
  end

  def look=(value : Look)
    @mutex.synchronize { @look = value }
  end

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

  def effect_by_name(name)
    effects.find { |effect| effect.effect.name == name.downcase.gsub(' ', '_') }
  end
end

enum Rosegold::Hand
  MainHand; OffHand
end
