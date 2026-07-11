require "./look"
require "./vec3"
require "./attribute_snapshot"

class Rosegold::Player
  # Registry ids for minecraft:movement_speed, index 22 in the attribute registry
  # of minecraft-data attributes.json for 1.21.8/1.21.9/1.21.11. 26.1/26.2 are not
  # published in minecraft-data; inherited from 774 and safe because physics falls
  # back to the effect formula whenever the attribute is absent.
  # Derived from each version's decompiled Attributes registration order;
  # 26.2 added 4 attributes before movement_speed (air_drag_modifier,
  # below_name_distance, bounciness, friction_modifier).
  MOVEMENT_SPEED_ATTRIBUTE_IDS = {
    772_u32 => 22_u32,
    773_u32 => 22_u32,
    774_u32 => 22_u32,
    775_u32 => 22_u32,
    776_u32 => 26_u32,
  }
  SPRINT_EXCLUDED_MODIFIER_IDS = Set{Rosegold::AttributeSnapshot::SPRINTING_MODIFIER_ID}

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
    experience_level : UInt32 = 0,
    total_experience : UInt32 = 0,
    experience_progress : Float32 = 0,
    hotbar_selection : UInt32 = 0,
    gamemode : Int8 = 0,
    effects : Array(EntityEffect) = [] of EntityEffect,
    flying_speed : Float32 = 0.05_f32,
    field_of_view_modifier : Float32 = 0.1_f32
  property attributes : Hash(UInt32, AttributeSnapshot) = Hash(UInt32, AttributeSnapshot).new
  property fall_distance : Float64 = 0.0
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

  def speed_level : Int32
    effects.find { |e| e.effect == EntityEffect::Effect::Speed }.try { |e| e.amplifier.to_i32 + 1 } || 0
  end

  def slowness_level : Int32
    effects.find { |e| e.effect == EntityEffect::Effect::Slowness }.try { |e| e.amplifier.to_i32 + 1 } || 0
  end

  def jump_boost_level : Int32
    effects.find { |e| e.effect == EntityEffect::Effect::JumpBoost }.try { |e| e.amplifier.to_i32 + 1 } || 0
  end

  def has_slow_falling? : Bool
    effects.any? { |e| e.effect == EntityEffect::Effect::SlowFalling }
  end

  def levitation_level : Int32
    effects.find { |e| e.effect == EntityEffect::Effect::Levitation }.try { |e| e.amplifier.to_i32 + 1 } || 0
  end

  def apply_attribute_snapshots(snapshots : Array(AttributeSnapshot)) : Nil
    snapshots.each { |snapshot| attributes[snapshot.attribute_id] = snapshot }
  end

  def movement_speed_attribute : AttributeSnapshot?
    id = MOVEMENT_SPEED_ATTRIBUTE_IDS[Rosegold::Client.protocol_version]?
    id ? attributes[id]? : nil
  end

  # Synced attribute already folds in Speed/Slowness; sprint is excluded here because
  # physics applies SPRINT_MULTIPLIER itself. Effect formula is the no-attribute fallback.
  def ground_movement_speed(base_movement_speed : Float64) : Float64
    if attribute = movement_speed_attribute
      Math.max(0.0, attribute.effective_value(excluding: SPRINT_EXCLUDED_MODIFIER_IDS))
    else
      Math.max(0.0, base_movement_speed * (1.0 + 0.2 * speed_level) * (1.0 - 0.15 * slowness_level))
    end
  end
end

enum Rosegold::Hand
  MainHand; OffHand
end
