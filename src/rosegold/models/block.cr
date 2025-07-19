require "json"

class Rosegold::Block
  include JSON::Serializable

  getter id : UInt16
  @[JSON::Field(key: "name")]
  getter id_str : String
  @[JSON::Field(key: "displayName")]
  getter display_name : String
  @[JSON::Field(key: "stackSize")]
  getter stack_size : UInt8
  @[JSON::Field(key: "minStateId")]
  getter min_state_id : UInt16
  @[JSON::Field(key: "maxStateId")]
  getter max_state_id : UInt16
  @[JSON::Field(key: "defaultState")]
  getter default_state : UInt16
  getter hardness : Float32 = -1.0
  @[JSON::Field(key: "harvestTools")]
  getter harvest_tools : Hash(String, Bool)?
  getter material : String

  # Not individual block states, but the properties that, in combination, make up each block state.
  # Empty array if block has only one state.
  getter states : Array(MCData::BlockProperty)

  def self.from_block_state_id(state_id : UInt16) : Block
    MCData::DEFAULT.blocks.find { |block| block.min_state_id <= state_id && block.max_state_id >= state_id } || \
       raise "Invalid block state id #{state_id}"
  end

  def material_tool_multipliers
    MCData::DEFAULT.materials.json_unmapped[material]
  end

  def best_tool?(slot : Slot)
    material_tool_multipliers
    slot.item_id_int.to_s
    material_tool_multipliers.as_h[slot.item_id_int.to_s]? || false
  end

  def can_harvest?(slot : Slot)
    return true if harvest_tools.nil?

    best_tool?(slot) || harvest_tools.try &.keys.includes? slot.item_id_int.to_s
  end

  def break_damage(main_hand : Slot, player : Player, creative : Bool = false) : Float64
    return 0_f64 if creative

    speed_multiplier = 1.0
    if best_tool?(main_hand)
      speed_multiplier = material_tool_multipliers[main_hand.item_id_int.to_s].as_f
      speed_multiplier += main_hand.efficiency ** 2 + 1 if main_hand.efficiency > 0
    end

    # TODO: Implement calculations for the following factors:
    # - mining fatigue
    # - in_water without aqua affinity

    if haste = player.effect_by_name("haste")
      speed_multiplier *= 1.0 + 0.2 * (haste.amplifier + 1)
    end

    speed_multiplier /= 5 if !player.on_ground?

    damage = speed_multiplier / hardness
    damage /= can_harvest?(main_hand) ? 30 : 100

    return 0_f64 if damage > 1

    damage
  end

  def break_time(main_hand : Slot, player : Player, creative : Bool = false) : Int32
    break_damage = break_damage(main_hand, player, creative)

    return 0 if break_damage.zero?

    (1.0 / break_damage).ceil.to_i
  end
end
