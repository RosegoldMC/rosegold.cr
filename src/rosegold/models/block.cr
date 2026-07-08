require "json"
require "minecraft-data"

# Runtime extensions to the minecraft-data schema block: break-speed and
# harvest logic that consults the active version's data and the held item.
class Minecraft::Data::Block
  def self.from_block_state_id(state_id : UInt16) : Minecraft::Data::Block
    Rosegold::MCData.default.blocks.find { |block| block.min_state_id <= state_id && block.max_state_id >= state_id } || \
       raise "Invalid block state id #{state_id}"
  end

  def material_tool_multipliers
    Rosegold::MCData.default.materials.json_unmapped[material]
  end

  def best_tool?(slot : Rosegold::Slot)
    material_tool_multipliers.as_h[slot.item_id_int.to_s]? || false
  end

  def can_harvest?(slot : Rosegold::Slot)
    return true if harvest_tools.nil?

    best_tool?(slot) || harvest_tools.try &.keys.includes? slot.item_id_int.to_s
  end

  # Search all materials for the tool's speed multiplier.
  # Handles cases where the block's material doesn't list all valid tools
  # (e.g. obsidian's "incorrect_for_wooden_tool" omits diamond/netherite pickaxes).
  def tool_speed_from_any_material(slot : Rosegold::Slot) : Float64?
    item_id = slot.item_id_int.to_s
    Rosegold::MCData.default.materials.json_unmapped.each_value do |multipliers|
      if speed = multipliers.as_h[item_id]?
        return speed.as_f
      end
    end
    nil
  end

  def break_damage(main_hand : Rosegold::Slot, player : Rosegold::Player, creative : Bool = false) : Float64
    return 0_f64 if creative

    speed_multiplier = 1.0
    if best_tool?(main_hand)
      speed_multiplier = material_tool_multipliers[main_hand.item_id_int.to_s].as_f
    elsif tool_speed = main_hand.tool_speed_for_tag(material)
      speed_multiplier = tool_speed.to_f64
    elsif harvest_tools.try &.has_key?(main_hand.item_id_int.to_s)
      if speed = tool_speed_from_any_material(main_hand)
        speed_multiplier = speed
      elsif tc = main_hand.tool_component
        speed_multiplier = tc.default_mining_speed.to_f64
      end
    end

    if speed_multiplier > 1.0 && main_hand.efficiency > 0
      speed_multiplier += main_hand.efficiency ** 2 + 1
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

    return 1_f64 if damage > 1

    damage
  end

  def break_time(main_hand : Rosegold::Slot, player : Rosegold::Player, creative : Bool = false) : Int32
    break_damage = break_damage(main_hand, player, creative)

    return 0 if break_damage.zero?

    (1.0 / break_damage).ceil.to_i
  end
end

module Rosegold
  alias Block = Minecraft::Data::Block
end
