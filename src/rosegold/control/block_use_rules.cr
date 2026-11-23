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

  # Plain Block registrations (no block class, one state, full-cube collision) whose
  # BlockItem is the default one; their use methods are the inherited PASS.
  private PLAIN_CUBES = Set(String).new(%w(
    stone granite diorite andesite cobblestone mossy_cobblestone dirt coarse_dirt sandstone clay
    obsidian smooth_stone stone_bricks bricks end_stone blackstone terracotta iron_block
    gold_block diamond_block oak_planks spruce_planks birch_planks jungle_planks acacia_planks
    dark_oak_planks cherry_planks mangrove_planks bamboo_planks crimson_planks warped_planks
    pale_oak_planks
  ))
  # Block classes in these chains never override useItemOn or useWithoutItem.
  private INERT_BLOCKS = Set(String).new(%w(grass_block podzol mycelium sand red_sand gravel netherrack))
  private WOODS        = %w(oak spruce birch jungle acacia cherry dark_oak pale_oak mangrove bamboo crimson warped poplar)
  private COPPERS      = %w(copper exposed_copper weathered_copper oxidized_copper
    waxed_copper waxed_exposed_copper waxed_weathered_copper waxed_oxidized_copper)
  private DOORS                 = (WOODS + COPPERS).map { |name| "#{name}_door" }
  private TRAPDOORS             = (WOODS + COPPERS).map { |name| "#{name}_trapdoor" }
  private FENCE_GATES           = WOODS.map { |name| "#{name}_fence_gate" }
  private HORIZONTAL_DIRECTIONS = {"south", "west", "north", "east"}
  private BUTTONS               = WOODS.map { |name| "#{name}_button" } + %w(stone_button polished_blackstone_button)
  private MENUS                 = %w(
    chest trapped_chest ender_chest barrel furnace blast_furnace smoker crafting_table
    anvil chipped_anvil damaged_anvil enchanting_table brewing_stand beacon hopper dispenser dropper
    crafter loom stonecutter grindstone smithing_table cartography_table shulker_box
  ) + %w(white orange magenta light_blue yellow lime pink gray light_gray cyan purple blue brown green red black).map { |color| "#{color}_shulker_box" }
  private CAULDRONS = {"cauldron", "water_cauldron", "lava_cauldron", "powder_snow_cauldron"}
  private FULL_CUBE = AABBd.new(0, 0, 0, 1, 1, 1)

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
    elsif DOORS.includes?(name)
      return toggle_door(dimension, mc, clicked, block, state) if hand.main_hand?
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    elsif FENCE_GATES.includes?(name)
      return toggle_fence_gate(mc, clicked, block, state, player.look.yaw) if hand.main_hand?
      return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
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

    return unknown unless INERT_BLOCKS.includes?(name) || plain_cube?(mc, block) || mc.air_states.includes?(state)
    return Decision.new(Result::Pass) if item_use_on_passes?(item, held)
    return unknown unless plain_cube?(mc, block) || mc.air_states.includes?(state)
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
    !!item && ItemUseRules.default_use_on_passes?(item.name, held)
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
    if (changed = toggle_property(name, property)) && (replacement = state_id(mc, block, changed))
      Decision.new(Result::Success, [{clicked, replacement}])
    else
      Decision.new(Result::Unknown)
    end
  end

  private def self.toggle_door(dimension : Dimension, mc : MCData, clicked : Vec3i, block : Block, state : UInt16) : Decision
    success = Decision.new(Result::Success)
    return success unless name = mc.block_state_names[state]?
    return success unless (changed = toggle_property(name, "open")) && (replacement = state_id(mc, block, changed))

    if name.includes?("half=lower")
      partner = adjacent(clicked, BlockFace::Top)
      half, other_half = "half=lower", "half=upper"
    elsif name.includes?("half=upper")
      partner = adjacent(clicked, BlockFace::Bottom)
      half, other_half = "half=upper", "half=lower"
    else
      return success
    end

    writes = [{clicked, replacement}]
    if (partner_state = block_state(dimension, partner)) &&
       (partner_block = block_for(mc, partner_state)) &&
       (DOORS.includes?(partner_block.id_str) || partner_block.id_str == "iron_door") &&
       mc.block_state_names[partner_state]?.try(&.includes?(other_half)) &&
       (partner_replacement = state_id(mc, block, changed.sub(half, other_half)))
      writes << {partner, partner_replacement}
    end
    Decision.new(Result::Success, writes)
  end

  private def self.toggle_fence_gate(mc : MCData, clicked : Vec3i, block : Block, state : UInt16, yaw : Float32) : Decision
    success = Decision.new(Result::Success)
    return success unless name = mc.block_state_names[state]?
    return success unless changed = toggle_property(name, "open")
    if name.includes?("open=false")
      return success unless yaw.finite?
      direction = (Look.wrap_yaw(yaw).to_f64 / 90.0 + 0.5).floor
      index = direction.to_i32 & 3
      opposite = HORIZONTAL_DIRECTIONS[(index + 2) & 3]
      changed = changed.sub("facing=#{opposite}", "facing=#{HORIZONTAL_DIRECTIONS[index]}")
    end
    return success unless replacement = state_id(mc, block, changed)
    Decision.new(Result::Success, [{clicked, replacement}])
  end

  private def self.toggle_property(name : String, property : String) : String?
    enabled = "#{property}=true"
    disabled = "#{property}=false"
    if name.includes?(enabled)
      name.sub(enabled, disabled)
    elsif name.includes?(disabled)
      name.sub(disabled, enabled)
    end
  end

  private def self.state_id(mc : MCData, block : Block, name : String) : UInt16?
    (block.min_state_id..block.max_state_id).find { |id| mc.block_state_names[id]? == name }
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
