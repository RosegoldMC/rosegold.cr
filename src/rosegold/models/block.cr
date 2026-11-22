require "json"
require "minecraft-data"

module Rosegold
  alias MiningBlockTags = Array(NamedTuple(name: String, entries: Array(UInt32)))
end

# Runtime extensions to the minecraft-data schema block: break-speed and
# harvest logic that consults the active version's data and the held item.
class Minecraft::Data::Block
  private TIER_SPEEDS = {
    "wooden"    => 2.0_f32,
    "stone"     => 4.0_f32,
    "copper"    => 5.0_f32,
    "iron"      => 6.0_f32,
    "diamond"   => 8.0_f32,
    "golden"    => 12.0_f32,
    "netherite" => 9.0_f32,
  }
  private MINING_TOOL_TYPES = {"axe", "hoe", "pickaxe", "shovel"}

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

  def can_harvest?(slot : Rosegold::Slot, *, block_tags : Rosegold::MiningBlockTags? = nil) : Bool
    mining_tool_properties(slot, block_tags)[1]
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

  def break_damage(main_hand : Rosegold::Slot, player : Rosegold::Player, creative : Bool = false, *,
                   submerged : Bool = player.in_water?, aqua_affinity : Bool = false,
                   block_tags : Rosegold::MiningBlockTags? = nil) : Float64
    return 0_f64 if creative || hardness < 0

    speed, correct_tool = mining_tool_properties(main_hand, block_tags)
    if speed > 1.0_f32
      if efficiency = player.mining_efficiency
        speed += efficiency
      elsif (level = main_hand.efficiency.to_f32) > 0
        speed += level * level + 1.0_f32
      end
    end

    haste = player.effects.find(&.effect.haste?)
    conduit = player.effects.find(&.effect.conduit_power?)
    if haste || conduit
      amplifier = Math.max(haste.try(&.amplifier) || 0_u32, conduit.try(&.amplifier) || 0_u32)
      speed *= 1.0_f32 + (amplifier.to_f32 + 1.0_f32) * 0.2_f32
    end

    if fatigue = player.effects.find(&.effect.mining_fatigue?)
      speed *= case fatigue.amplifier
               when 0 then 0.3_f32
               when 1 then 0.09_f32
               when 2 then 0.0027_f32
               else        0.00081_f32
               end
    end

    speed *= player.block_break_speed
    speed *= player.submerged_mining_speed(aqua_affinity) if submerged
    speed /= 5.0_f32 unless player.on_ground?
    return 0_f64 unless speed > 0

    damage = speed / hardness / (correct_tool ? 30.0_f32 : 100.0_f32)
    Math.min(1.0_f32, damage).to_f64
  end

  def break_time(main_hand : Rosegold::Slot, player : Rosegold::Player, creative : Bool = false, *,
                 submerged : Bool = player.in_water?, aqua_affinity : Bool = false,
                 block_tags : Rosegold::MiningBlockTags? = nil) : Int32
    damage = break_damage(main_hand, player, creative, submerged: submerged, aqua_affinity: aqua_affinity, block_tags: block_tags)
    return 0 if damage.zero?

    ticks = (1.0_f32 / damage.to_f32).ceil
    ticks.to_f64 <= Int32::MAX ? ticks.to_i32 : 0
  end

  private def mining_tool_properties(slot : Rosegold::Slot, block_tags : Rosegold::MiningBlockTags?) : Tuple(Float32, Bool)
    harvest = harvest_tools
    return {1.0_f32, harvest.nil?} if slot.empty? || slot.components_to_remove.includes?("tool")

    if tool = slot.tool_component
      return patched_tool_properties(tool, block_tags)
    end

    item_id = slot.item_id_int.to_s
    correct_tool = harvest.nil? || harvest[item_id]? == true
    item_name = Rosegold::MCData.default.items.find { |item| item.id == slot.item_id_int }.try(&.name)
    return {1.0_f32, correct_tool} unless item_name

    tier, _, kind = item_name.partition('_')
    if MINING_TOOL_TYPES.includes?(kind) && (tier_speed = TIER_SPEEDS[tier]?)
      tool_tag = "mineable/#{kind}"
      block_id = mining_registry_id if block_tags
      if block_id && block_tags
        matches = in_mining_tag?(tool_tag, block_tags, block_id)
        denied = harvest && in_mining_tag?("incorrect_for_#{tier == "golden" ? "gold" : tier}_tool", block_tags, block_id)
        return {matches ? tier_speed : 1.0_f32, harvest.nil? || (matches && !denied)}
      end

      # The shard can retain a tier restriction in place of the mineable tag.
      # Infer the tool family from the allowed harvest tools, never from the tier restriction itself.
      matches = material.split(';').includes?(tool_tag) || (material.starts_with?("incorrect_for_") &&
                                                            harvest && Rosegold::MCData.default.materials.json_unmapped[tool_tag]?.try { |row| harvest.keys.any? { |id| row.as_h.has_key?(id) } })
      return {matches ? tier_speed : 1.0_f32, correct_tool}
    end

    if item_name == "shears" || (kind == "sword" && TIER_SPEEDS.has_key?(tier))
      return {15.0_f32, true} if id_str == "cobweb"
      return {special_tool_speed(item_name == "shears", block_tags), harvest.nil?}
    end

    {1.0_f32, correct_tool}
  end

  private def patched_tool_properties(tool : Rosegold::DataComponents::Tool, block_tags : Rosegold::MiningBlockTags?) : Tuple(Float32, Bool)
    block_id = mining_registry_id
    speed = nil
    correct_tool = nil
    tool.rules.each do |rule|
      matches = if tag = rule.blocks_tag
                  in_mining_tag?(tag, block_tags, block_id)
                else
                  block_id && rule.blocks_ids.try(&.includes?(block_id))
                end
      next unless matches

      speed ||= rule.speed if rule.has_speed?
      correct_tool = rule.correct_for_drops? if correct_tool.nil? && rule.has_correct_for_drops?
    end
    {speed || tool.default_mining_speed, harvest_tools.nil? || correct_tool == true}
  end

  private def special_tool_speed(shears : Bool, block_tags : Rosegold::MiningBlockTags?) : Float32
    block_id = mining_registry_id if block_tags
    unless shears
      return Float32::MAX if in_mining_tag?("sword_instantly_mines", block_tags, block_id)
      return 1.5_f32 if in_mining_tag?("sword_efficient", block_tags, block_id) ||
                        (!block_tags && material.split(';').any? { |tag| tag == "plant" || tag == "leaves" || tag == "gourd" })
      return 1.0_f32
    end

    if block_tags && Rosegold::Client.protocol_version >= 776
      return 15.0_f32 if in_mining_tag?("shears_extreme_breaking_speed", block_tags, block_id)
      return 5.0_f32 if in_mining_tag?("shears_major_breaking_speed", block_tags, block_id)
      return 2.0_f32 if in_mining_tag?("shears_minor_breaking_speed", block_tags, block_id)
    else
      return 15.0_f32 if in_mining_tag?("leaves", block_tags, block_id)
      return 5.0_f32 if in_mining_tag?("wool", block_tags, block_id)
      return 2.0_f32 if id_str == "vine" || id_str == "glow_lichen"
    end
    1.0_f32
  end

  private def mining_registry_id : UInt32?
    Rosegold::MCData.default.blocks.index { |block| block.min_state_id == min_state_id }.try &.to_u32
  end

  private def in_mining_tag?(tag : String, block_tags : Rosegold::MiningBlockTags?, block_id : UInt32?) : Bool
    namespaced = tag.includes?(':') ? tag : "minecraft:#{tag}"
    if block_tags && block_id
      matches = block_tags.find { |entry| entry[:name] == namespaced }
      return matches.try(&.[:entries].includes?(block_id)) || false
    end

    namespaced.starts_with?("minecraft:") && material.split(';').includes?(namespaced.lchop("minecraft:"))
  end
end

module Rosegold
  alias Block = Minecraft::Data::Block
end
