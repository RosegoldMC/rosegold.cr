module Rosegold::BlockUseRules
  enum Result
    Pass
    Fail
    Consume
    Success
    Unknown
  end

  alias Write = Tuple(Vec3i, UInt16)
  record Decision, result : Result, writes : Array(Write) = [] of Write

  private PLAIN_CUBES = {"stone", "cobblestone", "obsidian", "oak_planks", "spruce_planks", "birch_planks"}
  private WOODS       = %w(oak spruce birch jungle acacia cherry dark_oak pale_oak mangrove bamboo crimson warped poplar)
  private TRAPDOORS   = WOODS.map { |name| "#{name}_trapdoor" } + %w(
    copper_trapdoor exposed_copper_trapdoor weathered_copper_trapdoor oxidized_copper_trapdoor
    waxed_copper_trapdoor waxed_exposed_copper_trapdoor waxed_weathered_copper_trapdoor waxed_oxidized_copper_trapdoor
  )
  private BUTTONS = WOODS.map { |name| "#{name}_button" } + %w(stone_button polished_blackstone_button)
  private MENUS   = %w(
    chest trapped_chest ender_chest barrel furnace blast_furnace smoker crafting_table
    anvil chipped_anvil damaged_anvil enchanting_table brewing_stand beacon hopper dispenser dropper
    crafter loom stonecutter grindstone smithing_table cartography_table shulker_box
  ) + %w(white orange magenta light_blue yellow lime pink gray light_gray cyan purple blue brown green red black).map { |color| "#{color}_shulker_box" }
  private CAULDRONS = {"cauldron", "water_cauldron", "lava_cauldron", "powder_snow_cauldron"}
  # Registered as plain Items, so Item#useOn returns its default PASS.
  private DEFAULT_USE_ON_ITEMS = {"apple", "bread"}
  private FULL_CUBE            = AABBd.new(0, 0, 0, 1, 1, 1)

  def self.evaluate(dimension : Dimension, player : Player, clicked : Vec3i, face : BlockFace, hand : Hand, main_hand : Slot, off_hand : Slot) : Decision
    unknown = Decision.new(Result::Unknown)
    return unknown unless {0, 1}.includes?(player.gamemode) && player.creative_mode? == (player.gamemode == 1)
    return unknown unless state = block_state(dimension, clicked)
    mc = MCData.default
    return unknown unless block = block_for(mc, state)
    held = hand.main_hand? ? main_hand : off_hand
    item = mc.items.bsearch { |candidate| candidate.id >= held.item_id_int } unless held.empty?
    return unknown if !held.empty? && (!item || item.id != held.item_id_int || item.name == "air")

    name = block.id_str
    if player.sneaking? && (!main_hand.empty? || !off_hand.empty?)
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    elsif CAULDRONS.includes?(name)
      return Decision.new(Result::Pass) unless item
      return unknown if patched?(held)
      return Decision.new(cauldron_result(dimension, mc, clicked, block, state, item.name))
    elsif TRAPDOORS.includes?(name)
      return change_property(mc, clicked, block, state, "open") if hand.main_hand?
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    elsif BUTTONS.includes?(name)
      if hand.main_hand?
        return Decision.new(Result::Consume) if mc.block_state_names[state].includes?("powered=true")
        return change_property(mc, clicked, block, state, "powered")
      end
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    elsif name == "lever" || MENUS.includes?(name)
      return Decision.new(Result::Success) if hand.main_hand?
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    elsif name == "lectern"
      return Decision.new(Result::Success) if hand.main_hand? && mc.block_state_names[state].includes?("has_book=true")
      if item_use_on_passes?(item, held)
        return Decision.new(hand.main_hand? && held.present? ? Result::Consume : Result::Pass)
      end
    elsif {"iron_door", "iron_trapdoor"}.includes?(name)
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    end

    return unknown unless plain_cube?(mc, block) || mc.air_states.includes?(state)
    return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    return unknown unless item && PLAIN_CUBES.includes?(item.name)
    return unknown if patched?(held)

    placed = mc.blocks.find { |candidate| candidate.id_str == item.name }
    return unknown unless placed && plain_cube?(mc, placed)
    position = mc.air_states.includes?(state) ? clicked : adjacent(clicked, face)
    return unknown unless target = block_state(dimension, position)
    unless mc.air_states.includes?(target)
      return Decision.new(Result::Fail) if (obstruction = block_for(mc, target)) && plain_cube?(mc, obstruction)
      return unknown
    end
    box = FULL_CUBE.offset(position.to_f64)
    return Decision.new(Result::Fail) if box.intersects?(player.aabb)
    return unknown if dimension.entities.any? { |id, entity| id != player.entity_id && box.intersects?(entity.bounding_box) }
    return unknown unless known_neighbors?(dimension, mc, position)

    Decision.new(Result::Success, [{position, placed.min_state_id}])
  end

  private def self.block_for(mc : MCData, state : UInt16) : Block?
    block = mc.blocks.bsearch { |candidate| candidate.max_state_id >= state }
    block if block && block.min_state_id <= state
  end

  private def self.block_state(dimension : Dimension, position : Vec3i) : UInt16?
    return unless -30_000_000 <= position.x < 30_000_000 && -30_000_000 <= position.z < 30_000_000
    return unless 0 <= position.y.to_i64 - dimension.min_y < dimension.world_height
    dimension.interaction_block_state(position)
  end

  private def self.adjacent(position : Vec3i, face : BlockFace) : Vec3i
    offset = face.to_vec3d(1.0)
    position + Vec3i.new(offset.x.to_i32, offset.y.to_i32, offset.z.to_i32)
  end

  private def self.known_neighbors?(dimension : Dimension, mc : MCData, position : Vec3i) : Bool
    BlockFace.values.all? do |face|
      state = block_state(dimension, adjacent(position, face))
      next false unless state
      next true if mc.air_states.includes?(state)
      block = block_for(mc, state)
      !!(block && plain_cube?(mc, block))
    end
  end

  private def self.item_use_on_passes?(item, held : Slot) : Bool
    return true if held.empty?
    !!item && DEFAULT_USE_ON_ITEMS.includes?(item.name) && !patched?(held)
  end

  private def self.patched?(held : Slot) : Bool
    !held.components_to_add.empty? || !held.components_to_remove.empty?
  end

  private def self.plain_cube?(mc : MCData, block : Block) : Bool
    return false unless PLAIN_CUBES.includes?(block.id_str) && block.min_state_id == block.max_state_id && block.states.empty?
    shape = mc.block_state_collision_shapes[block.min_state_id]
    shape.size == 1 && shape[0].to_f64 == FULL_CUBE
  end

  private def self.change_property(mc : MCData, clicked : Vec3i, block : Block, state : UInt16, property : String) : Decision
    name = mc.block_state_names[state]
    enabled = "#{property}=true"
    disabled = "#{property}=false"
    if name.includes?(enabled)
      changed = name.sub(enabled, disabled)
    elsif name.includes?(disabled)
      changed = name.sub(disabled, enabled)
    else
      return Decision.new(Result::Unknown)
    end

    replacement = (block.min_state_id..block.max_state_id).find { |id| mc.block_state_names[id] == changed }
    replacement ? Decision.new(Result::Success, [{clicked, replacement}]) : Decision.new(Result::Unknown)
  end

  private def self.cauldron_result(dimension : Dimension, mc : MCData, clicked : Vec3i, block : Block, state : UInt16, item : String) : Result
    case item
    when "water_bucket"
      Result::Success
    when "lava_bucket", "powder_snow_bucket"
      above = block_state(dimension, adjacent(clicked, BlockFace::Top))
      return Result::Unknown unless above
      return Result::Success if mc.air_states.includes?(above)
      above_block = block_for(mc, above)
      return Result::Unknown unless above_block
      return Result::Success if plain_cube?(mc, above_block)
      above_block.id_str == "water" ? Result::Consume : Result::Unknown
    when "bucket"
      return Result::Success if block.id_str == "lava_cauldron"
      if block.id_str != "cauldron" && state == block.max_state_id &&
         block.states.first?.try(&.values) == %w(1 2 3)
        return Result::Success
      end
      Result::Unknown
    else
      Result::Unknown
    end
  end
end
