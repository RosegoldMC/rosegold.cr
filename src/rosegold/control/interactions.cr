require "../client"
require "../world/look"
require "../world/vec3"
require "./physics"

class Rosegold::Interactions
  private class ReachedBlock
    getter intercept : Vec3d, block : Vec3i, face : BlockFace
    getter? inside_block : Bool

    def initialize(@intercept, @block, @face, @inside_block = false); end
  end

  # Random 3-6 ticks between attacks (~3.3-6.7 CPS), under CivMC 8 CPS cap.
  ATTACK_COOLDOWN_RANGE = 3..6

  private HELD_DESTROY_DELAY =  5
  private MINING_MISS_DELAY  = 10
  private alias MiningItem = {UInt32, Hash(String, Bytes), Set(String)}

  @using_hand = nil
  @using_hand_started = false
  @queued_hand_tap = nil
  getter last_hand_tap_sequence : Int32 = 0
  @using_hand_delay = 0_i32
  # Releasing food cancels its repeat delay, but must not bypass the click cooldown.
  @use_cooldown_ticks = 0_i32
  getter digging_block : ReachedBlock?
  @attack_queued = false
  @dig_released = false
  @destroy_delay = 0
  @mining_miss_ticks = 0
  @destroying_item : MiningItem?
  @attack_cooldown_ticks : Int32 = 0
  getter block_damage_progress = 0_f32
  @sent_held_item_index : UInt32?

  getter client : Client
  property? digging : Bool = false

  def initialize(@client)
  end

  # Activates the "use" button.
  def start_using_hand(hand : Hand = :main_hand) # TODO: Auto select hand each tick
    return if @using_hand == hand

    stop_using_hand if @using_hand
    @using_hand = hand
    @using_hand_started = false
    @using_hand_delay = 0
  end

  # Queues one use-button press without holding it.
  def tap_using_hand(hand : Hand = :main_hand)
    stop_using_hand if @using_hand
    @queued_hand_tap = hand
  end

  # Deactivates the "use" button.
  def stop_using_hand
    hand_was_started = @using_hand_started

    @using_hand = nil
    @using_hand_started = false
    @queued_hand_tap = nil
    @using_hand_delay = 0
    finish_using_hand if hand_was_started
  end

  private def finish_using_hand
    client.player.using_item = false
    sequence = client.next_sequence
    operation = BlockOperation.new(Vec3i::ORIGIN, :use)
    client.pending_block_operations[sequence] = operation

    send_packet Serverbound::PlayerAction.new :finish_using_hand, Vec3i::ORIGIN, :bottom, sequence
  end

  # Activates the "attack" button.
  def start_digging
    return if digging?

    self.digging = true
    @attack_queued = true
  end

  # Deactivates the "attack" button.
  def stop_digging
    return unless digging?

    self.digging = false
    @dig_released = true
  end

  def reset_mining
    self.digging = false
    @attack_queued = false
    @dig_released = false
    @destroy_delay = 0
    @mining_miss_ticks = 0
    @sent_held_item_index = nil
    clear_dig_target
  end

  def tick
    return unless client.connected?
    tick_held_item
    # Vanilla order: attack presses, use, then the held attack, so use sees a
    # staged break that this tick's press started.
    continuation = tick_attack
    tick_using_hand
    tick_continue_attack(continuation)
  end

  private def tick_held_item
    if @sent_held_item_index != client.player.hotbar_selection
      @sent_held_item_index = client.player.hotbar_selection
      send_packet Serverbound::HeldItemChange.new client.player.hotbar_selection
    end
  end

  def swap_hands : Nil
    tick_held_item
    send_packet Serverbound::PlayerAction.new :swap_hands
  end

  # Returns the press's cached block hit to continue on, true to continue a
  # held attack on a fresh ray, or false to skip the held attack this tick.
  private def tick_attack : ReachedBlock | Bool
    click_ready = @attack_cooldown_ticks == 0
    @attack_cooldown_ticks -= 1 unless click_ready

    if @dig_released
      @dig_released = false
      @mining_miss_ticks = 0
      cancel_digging
    end

    miss_delayed = @mining_miss_ticks > 0
    @mining_miss_ticks -= 1 if miss_delayed

    if client.player.using_item?
      @attack_queued = false
      return false
    end

    fresh_click = click_ready && @attack_queued
    if fresh_click
      @attack_queued = false
      if (entity = reach_block_or_entity).is_a?(Entity)
        if Client.protocol_version >= 775_u32
          send_packet Serverbound::Attack.new entity.entity_id
        else
          send_packet Serverbound::InteractEntity.new entity.entity_id, :attack
        end
        send_swing attack: true
        @attack_cooldown_ticks = rand(ATTACK_COOLDOWN_RANGE)
        @destroy_delay = HELD_DESTROY_DELAY if Client.protocol_version >= 777_u32 && client.player.creative_mode?
        cancel_digging
        return false
      end
    end

    return false if miss_delayed
    fresh_click ? start_attack_block : true
  end

  private def start_attack_block : ReachedBlock | Bool
    unless can_mine?
      cancel_digging
      return false
    end

    reached = reach_block_or_entity_unified(mining: true)
    unless reached.is_a?(ReachedBlock)
      if reached.nil? && digging? && client.player.gamemode != 1
        @mining_miss_ticks = MINING_MISS_DELAY - 1
      end
      cancel_digging
      return false
    end

    if start_digging(reached)
      return reached if @digging_block
      return reached if client.player.creative_mode? && !mining_air?(reached)
    end
    cancel_digging unless digging?
    false
  end

  private def tick_continue_attack(continuation : ReachedBlock | Bool) : Nil
    return if client.player.using_item?

    case continuation
    when ReachedBlock
      digging? ? continue_digging(continuation) : cancel_digging
    when true
      continue_held_attack
    end
  end

  private def continue_held_attack
    unless digging? && can_mine?
      cancel_digging
      return
    end

    reached = reach_block_or_entity_unified(mining: true)
    unless reached.is_a?(ReachedBlock)
      cancel_digging
      return
    end

    @attack_queued = false
    continue_digging(reached)
  end

  private def continue_digging(reached : ReachedBlock)
    if @destroy_delay > 0
      @destroy_delay -= 1
      send_swing attack: true
      return
    end

    active = @digging_block
    if client.player.creative_mode? || !active || !same_dig_target?(reached)
      start_digging(reached)
      return
    end

    return unless state = mining_block_state(reached)
    @block_damage_progress += break_damage(state)

    if @block_damage_progress >= 1_f32
      clear_dig_target
      @destroy_delay = HELD_DESTROY_DELAY
      send_dig_action(:finish, reached, predict: can_predict_break?(state))
    elsif Client.protocol_version >= 777_u32 && active.face != reached.face
      @digging_block = reached
      send_packet Serverbound::PlayerAction.new(:change_destroy_direction, reached.block, reached.face)
    end

    send_swing attack: true
  end

  private def tick_using_hand
    @using_hand_delay -= 1 if @using_hand_delay > 0
    @use_cooldown_ticks -= 1 if @use_cooldown_ticks > 0
    # Vanilla ignores use presses during a staged break; a held use retries.
    if @digging_block
      @queued_hand_tap = nil
      return
    end
    return if @using_hand_delay > 0 || @use_cooldown_ticks > 0

    if using_hand = @using_hand || @queued_hand_tap
      hand_tap = @using_hand.nil?
      held_slot = using_hand.main_hand? ? inventory.main_hand : inventory.off_hand
      @using_hand_delay = using_hand_delay_for held_slot
      @use_cooldown_ticks = 4
      @queued_hand_tap = nil
      case reached = reach_block_or_entity
      when Entity
        Log.debug { "Interacting with entity #{reached.entity_id}" }
        send_packet Serverbound::InteractEntity.new reached.entity_id.to_u64, :interact, hand: using_hand
        send_swing using_hand
      when ReachedBlock
        Log.debug { "Reached block: #{reached.block} at #{reached.intercept} face #{reached.face}" }
        place_block using_hand, reached, hand_tap: hand_tap

        # Vanilla falls through to UseItem when the block-use result is PASS.
        # Sneaking with an item in either hand bypasses block-use entirely.
        bypass_block_use = client.player.sneaking? &&
                           (inventory.main_hand.present? || inventory.off_hand.present?)
        if bypass_block_use || !block_use_consumes_click?(reached, using_hand)
          sequence = client.next_sequence
          operation = BlockOperation.new(Vec3i::ORIGIN, :use)
          client.pending_block_operations[sequence] = operation
          @last_hand_tap_sequence = sequence if hand_tap

          send_packet Serverbound::UseItem.new using_hand, sequence, client.player.look.yaw, client.player.look.pitch
        end
      else
        Log.debug { "No block or entity reached" }

        sequence = client.next_sequence
        operation = BlockOperation.new(Vec3i::ORIGIN, :use)
        client.pending_block_operations[sequence] = operation
        @last_hand_tap_sequence = sequence if hand_tap

        send_packet Serverbound::UseItem.new using_hand, sequence, client.player.look.yaw, client.player.look.pitch
      end
      if @using_hand
        @using_hand_started = true
      else
        finish_using_hand
        @using_hand_delay = 0
      end
    end
  end

  def using_hand_delay_for(slot)
    if slot.edible?
      32
    else
      4
    end
  end

  private def send_packet(packet)
    client.send_packet! packet
  end

  private def send_swing(hand : Hand = :main_hand, attack : Bool = false)
    if Client.protocol_version >= 777_u32
      send_packet Serverbound::Punch.new if attack
    else
      send_packet Serverbound::SwingArm.new hand
    end
    animation = Client.protocol_version >= 777_u32 ? swing_animation(hand, attack) : nil
    client.emit_event Event::ArmSwing.new(hand, animation)
  end

  private def swing_animation(hand : Hand, attack : Bool) : DataComponents::SwingAnimation
    slot = hand.main_hand? ? inventory.main_hand : inventory.off_hand
    component_name = attack ? "attack_animation" : "interact_animation"
    component = slot.components_to_add[component_name]?
    return component if component.is_a?(DataComponents::SwingAnimation)

    return default_swing_animation if slot.components_to_remove.includes?(component_name)
    return default_swing_animation unless attack

    case slot.name
    when "wooden_spear"    then DataComponents::SwingAnimation.new(2_u32, 13_u32)
    when "stone_spear"     then DataComponents::SwingAnimation.new(2_u32, 15_u32)
    when "copper_spear"    then DataComponents::SwingAnimation.new(2_u32, 17_u32)
    when "iron_spear"      then DataComponents::SwingAnimation.new(2_u32, 19_u32)
    when "golden_spear"    then DataComponents::SwingAnimation.new(2_u32, 19_u32)
    when "diamond_spear"   then DataComponents::SwingAnimation.new(2_u32, 21_u32)
    when "netherite_spear" then DataComponents::SwingAnimation.new(2_u32, 23_u32)
    else                        default_swing_animation
    end
  end

  private def default_swing_animation : DataComponents::SwingAnimation
    DataComponents::SwingAnimation.new(1_u32, 6_u32)
  end

  private def place_block(hand : Hand, reached : ReachedBlock, hand_tap : Bool = false)
    cursor = (reached.intercept - reached.block.to_f64).to_f32

    sequence = client.next_sequence
    operation = BlockOperation.new(reached.block, :place)
    client.pending_block_operations[sequence] = operation
    @last_hand_tap_sequence = sequence if hand_tap

    send_packet Serverbound::PlayerBlockPlacement.new \
      hand, reached.block, reached.face, cursor, reached.inside_block?, sequence
    send_swing hand
  end

  # Suppress UseItem fall-through when vanilla consumes the block interaction.
  # Unknown/unloaded block states do not consume.
  private def block_use_consumes_click?(reached : ReachedBlock, hand : Hand) : Bool
    block_state = client.dimension.block_state(reached.block)
    return false unless block_state
    block = Block.from_block_state_id(block_state)
    case block.id_str
    when "chest", "trapped_chest", "ender_chest", "barrel",
         .ends_with?("shulker_box"),
         "furnace", "blast_furnace", "smoker", "crafting_table",
         .ends_with?("anvil"),
         "enchanting_table", "brewing_stand", "beacon", "hopper",
         "dispenser", "dropper", "crafter", "loom", "stonecutter",
         "grindstone", "smithing_table", "cartography_table", "lectern",
         "chiseled_bookshelf"
      true
    when "lever", .ends_with?("button"), "repeater", "comparator",
         "note_block", "jukebox", "daylight_detector"
      true
    when "iron_door", "iron_trapdoor"
      false
    when .ends_with?("door"), .ends_with?("trapdoor"), .ends_with?("fence_gate")
      true
    when .ends_with?("bed"), "flower_pot", .starts_with?("potted_"),
         .ends_with?("sign"), "bell", "cake"
      true
    when "cauldron", "water_cauldron", "lava_cauldron", "powder_snow_cauldron"
      cauldron_use_consumes_click?(block, block_state, hand)
    else
      false
    end
  end

  private def cauldron_use_consumes_click?(block : Block, block_state : UInt16, hand : Hand) : Bool
    held_item_name = (hand.main_hand? ? inventory.main_hand : inventory.off_hand).name
    return true if {"water_bucket", "lava_bucket", "powder_snow_bucket"}.includes?(held_item_name)
    return false unless held_item_name == "bucket"

    case block.id_str
    when "lava_cauldron"
      true
    when "water_cauldron", "powder_snow_cauldron"
      block_state == block.max_state_id
    else
      false
    end
  end

  private def start_digging(reached : ReachedBlock) : Bool
    creative = client.player.creative_mode?
    return false unless state = mining_block_state(reached)
    return true if !creative && same_dig_target?(reached)

    cancel_digging(reached.face)
    if creative
      @destroy_delay = HELD_DESTROY_DELAY
      send_dig_action(:start, reached, predict: can_predict_break?(state))
    elsif break_damage(state) >= 1_f32
      send_dig_action(:start, reached, predict: can_predict_break?(state))
    else
      @digging_block = reached
      @destroying_item = mining_item_snapshot(inventory.main_hand)
      send_dig_action(:start, reached, predict: false)
    end
    send_swing attack: true
    true
  end

  private def mining_block_state(reached : ReachedBlock) : UInt16?
    block = reached.block
    client.dimension.mining_block_state(block.x, block.y, block.z)
  end

  private def mining_air?(reached : ReachedBlock) : Bool
    state = mining_block_state(reached)
    state.nil? || MCData.default.air_states.includes?(state)
  end

  private def break_damage(state : UInt16) : Float32
    Block.from_block_state_id(state).break_damage(inventory.main_hand, client.player, **client.mining_context).to_f32
  end

  private def can_mine? : Bool
    held = inventory.main_hand
    return false if held.components_to_add.has_key?("piercing_weapon")
    if Client.protocol_version >= 774_u32 && !held.empty? && !held.components_to_remove.includes?("piercing_weapon")
      return false if held_item_name(held).try(&.ends_with?("_spear"))
    end

    case client.player.gamemode
    when 0, 1 then true
    when 2    then held.components_to_add.has_key?("can_break")
    else           false
    end
  end

  private def held_item_name(held : Slot) : String?
    MCData.default.items.find { |item| item.id == held.item_id_int }.try(&.name)
  end

  private def can_predict_break?(state : UInt16) : Bool
    return false if client.player.gamemode == 2
    case Block.from_block_state_id(state).id_str
    when "command_block", "chain_command_block", "repeating_command_block", "structure_block", "jigsaw", "test_block", "test_instance_block"
      return false
    end

    held = inventory.main_hand
    name = held_item_name(held) unless held.empty?
    return false if name == "debug_stick"
    return true unless client.player.creative_mode?

    return true if held.empty?
    if tool = held.tool_component
      return tool.can_destroy_blocks_in_creative?
    end
    return true if held.components_to_remove.includes?("tool")

    return false unless name
    !name.ends_with?("_sword") && name != "mace" && name != "trident"
  end

  private def same_dig_target?(reached : ReachedBlock) : Bool
    @digging_block.try(&.block) == reached.block && @destroying_item == mining_item_snapshot(inventory.main_hand)
  end

  private def mining_item_snapshot(slot : Slot) : MiningItem
    components = {} of String => Bytes
    return {0_u32, components, Set(String).new} if slot.empty?

    slot.components_to_add.each do |name, component|
      buffer = Minecraft::IO::Memory.new
      if component.is_a?(DataComponents::Enchantments)
        buffer.write component.enchantments.size
        component.enchantments.keys.sort!.each do |id|
          buffer.write id
          buffer.write component.enchantments[id]
        end
      else
        component.write(buffer)
      end
      components[name] = buffer.to_slice
    end
    {slot.item_id_int, components, slot.components_to_remove.dup}
  end

  private def send_dig_action(status : Serverbound::PlayerAction::Status, reached : ReachedBlock, *, predict : Bool)
    sequence = client.next_sequence
    client.pending_block_operations[sequence] = BlockOperation.new(reached.block, :dig)
    client.dimension.predict_block_break(reached.block, sequence) if predict
    send_packet Serverbound::PlayerAction.new(status, reached.block, reached.face, sequence)
  end

  private def cancel_digging(face : BlockFace = :bottom)
    reached = @digging_block
    return unless reached

    clear_dig_target
    send_packet Serverbound::PlayerAction.new(:cancel, reached.block, face)
  end

  private def clear_dig_target
    @digging_block = nil
    @destroying_item = nil
    @block_damage_progress = 0_f32
  end

  private def reach_block_or_entity : ReachedBlock? | Rosegold::Entity?
    reach_block_or_entity_unified
  end

  private def reach_block : ReachedBlock?
    eyes = client.player.eyes
    reach_block_along eyes, reach_vec
  end

  private def reach_entity : Rosegold::Entity?
    client.dimension.raycast_entity client.player.eyes, entity_reach_vec, entity_reach_length, client.player.entity_id.to_u32
  end

  # Unified raytracing that properly handles both entities and blocks
  # ensuring entities cannot be hit through blocks
  private def reach_block_or_entity_unified(*, mining : Bool = false) : ReachedBlock? | Rosegold::Entity?
    eyes = client.player.eyes
    reach_vector = mining ? client.player.look.to_vec3 * client.player.block_interaction_range : reach_vec

    entity_boxes = [] of AABBd
    entity_map = [] of Rosegold::Entity

    reach_aabb = AABBd.new(eyes, eyes + reach_vector)
    client.dimension.entities.each_value do |entity|
      next unless entity.pickable?

      entity_bounding_box = entity.bounding_box
      if entity.passenger_ids.includes?(client.player.entity_id.to_u32)
        return entity if entity_bounding_box.contains?(eyes)
        next
      end
      # Vanilla picks an entity around the eyes, which an entry-face ray misses.
      return entity if mining && entity_bounding_box.contains?(eyes)
      if reach_aabb.intersects?(entity_bounding_box)
        entity_boxes << entity_bounding_box
        entity_map << entity
      end
    end

    block_hit = reach_block_along eyes, reach_vector, mining: mining
    entity_hit = Raytrace.raytrace(eyes, reach_vector, entity_boxes)
    return block_hit unless entity_hit

    entity_distance_sq = eyes.dist_sq(entity_hit.intercept)
    return block_hit if block_hit && entity_distance_sq >= eyes.dist_sq(block_hit.intercept)

    entity_map[entity_hit.box_nr] if entity_distance_sq < entity_reach_length ** 2
  end

  private def block_reach_length
    client.player.gamemode == 1 ? 5.0 : 4.5
  end

  private def entity_reach_length
    client.player.gamemode == 1 ? 5.0 : 3.0
  end

  private def reach_vec
    client.player.look.to_vec3 * block_reach_length
  end

  private def entity_reach_vec
    client.player.look.to_vec3 * entity_reach_length
  end

  # Like vanilla's BlockGetter.clip: visits the cells the ray passes through in
  # order and returns the first whose outline is hit. A cell owns its outline even
  # where it extends outside the cell (piston arms, offset plants).
  private def reach_block_along(start : Vec3d, reach : Vec3d, *, mining : Bool = false) : ReachedBlock?
    mcdata = MCData.default
    held = inventory.main_hand
    held_id = held.item_id_int unless held.empty?
    each_traversed_cell(start, reach) do |cell_x, cell_y, cell_z|
      # outside world or outside loaded chunks
      state = if mining
                client.dimension.mining_block_state(cell_x, cell_y, cell_z)
              else
                client.dimension.block_state(cell_x, cell_y, cell_z)
              end
      next unless block_state = state
      shape = mcdata.block_state_outline_shapes[block_state]
      if held_id && (by_item = mcdata.held_outline_shapes[block_state]?)
        shape = by_item[held_id]? || shape
      end
      next if shape.empty?
      dx = dy = dz = 0.0
      if offset = mcdata.outline_offset(block_state, cell_x, cell_z)
        dx, dy, dz = offset
      end
      boxes = shape.map &.to_f64.offset(cell_x + dx, cell_y + dy, cell_z + dz)
      hit = inside_block_hit(start, reach, boxes, Vec3i.new(cell_x, cell_y, cell_z)) ||
            Raytrace.raytrace(start, reach, boxes).try do |reached|
              ReachedBlock.new reached.intercept, Vec3i.new(cell_x, cell_y, cell_z), reached.face
            end
      return hit if hit
    end
    nil
  end

  private def each_traversed_cell(start : Vec3d, reach : Vec3d, &)
    finish = start + reach
    span = finish - start
    return if span.x.zero? && span.y.zero? && span.z.zero?

    padding = span * 1e-7
    origin = start - padding
    delta = (finish + padding) - origin
    x, y, z = origin.x.floor.to_i32, origin.y.floor.to_i32, origin.z.floor.to_i32
    step_x, step_y, step_z = delta.x.sign, delta.y.sign, delta.z.sign
    inf = Float64::INFINITY
    delta_x = step_x == 0 ? inf : 1.0 / delta.x.abs
    delta_y = step_y == 0 ? inf : 1.0 / delta.y.abs
    delta_z = step_z == 0 ? inf : 1.0 / delta.z.abs
    frac_x, frac_y, frac_z = origin.x - x, origin.y - y, origin.z - z
    max_x = step_x == 0 ? inf : delta_x * (step_x > 0 ? 1.0 - frac_x : frac_x)
    max_y = step_y == 0 ? inf : delta_y * (step_y > 0 ? 1.0 - frac_y : frac_y)
    max_z = step_z == 0 ? inf : delta_z * (step_z > 0 ? 1.0 - frac_z : frac_z)
    yield x, y, z
    while max_x <= 1.0 || max_y <= 1.0 || max_z <= 1.0
      if max_x < max_y && max_x < max_z
        x += step_x
        max_x += delta_x
      elsif max_y < max_z
        y += step_y
        max_y += delta_y
      else
        z += step_z
        max_z += delta_z
      end
      yield x, y, z
    end
  end

  # Vanilla treats a ray whose first sliver lies inside an outline (cobweb,
  # portal, vine) as hitting it at that point, facing against the dominant look axis.
  private def inside_block_hit(start : Vec3d, reach : Vec3d, boxes : Array(AABBd), block : Vec3i) : ReachedBlock?
    return nil if reach.x * reach.x + reach.y * reach.y + reach.z * reach.z < 1e-7
    point = start + reach * 0.001
    inside = boxes.any? do |box|
      (box.min.x <= point.x < box.max.x) &&
        (box.min.y <= point.y < box.max.y) &&
        (box.min.z <= point.z < box.max.z)
    end
    return nil unless inside
    ax, ay, az = reach.x.abs, reach.y.abs, reach.z.abs
    face = if ay >= ax && ay >= az
             reach.y > 0 ? BlockFace::Bottom : BlockFace::Top
           elsif az >= ax
             reach.z > 0 ? BlockFace::North : BlockFace::South
           else
             reach.x > 0 ? BlockFace::West : BlockFace::East
           end
    ReachedBlock.new point, block, face, inside_block: true
  end

  private def inventory : Inventory
    @inventory ||= Inventory.new client
  end
end
