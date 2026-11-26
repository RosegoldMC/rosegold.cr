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

  private struct ReachedEntity
    getter entity : Entity, intercept : Vec3d

    def initialize(@entity, @intercept); end
  end

  private class ActiveUse
    getter hand : Hand, item_id : UInt32, sequence : Int32?
    property ticks_left : Int32
    property? acknowledged = false

    def initialize(@hand, @item_id, @sequence = nil, @ticks_left = 0); end

    def provisional? : Bool
      !sequence.nil?
    end

    def confirm : Nil
      @sequence = nil
    end
  end

  private record UseRequest, hand : Hand?

  private HELD_DESTROY_DELAY =  5
  private MINING_MISS_DELAY  = 10
  private HELD_USE_DELAY     =  4
  # Vanilla clients never complete a use locally (LivingEntity.updateUsingItem);
  # these only bound a prediction the server has not confirmed.
  private PROVISIONAL_USE_TICKS     = 20
  private PROVISIONAL_USE_ACK_GRACE =  5
  private alias MiningItem = {UInt32, Hash(String, Bytes), Set(String)}
  private alias InteractionHit = ReachedBlock | ReachedEntity | Nil

  @held_use : UseRequest?
  @queued_use : UseRequest?
  @use_revision = 0_u64
  @active_use : ActiveUse?
  getter last_hand_tap_sequence : Int32 = 0
  @use_repeat_delay = 0
  getter digging_block : ReachedBlock?
  @attack_queued = false
  @manual_use_held = false
  @staged_action_release_pending = false
  @destroy_delay = 0
  @mining_miss_ticks = 0
  @destroying_item : MiningItem?
  getter block_damage_progress = 0_f32

  def block_break_target : Vec3i?
    @digging_block.try(&.block)
  end

  @sent_held_item_index : UInt32?

  getter client : Client
  property? digging : Bool = false

  def initialize(@client)
  end

  # A nil *hand* tries the main hand, then the off hand when the main hand passes.
  def start_using_hand(hand : Hand? = :main_hand)
    return unless client.manual_control.script_write_allowed?("start_using_hand")
    hold_use hand
  end

  # A nil *hand* tries the main hand, then the off hand when the main hand passes.
  def tap_using_hand(hand : Hand? = :main_hand)
    return unless client.manual_control.script_write_allowed?("tap_using_hand")
    press_use hand
  end

  def stop_using_hand
    return unless client.manual_control.script_write_allowed?("stop_using_hand")
    release_use
  end

  private def hold_use(hand : Hand?)
    return if (held = @held_use) && held.hand == hand

    @use_revision += 1
    @held_use = @queued_use = UseRequest.new(hand)
  end

  private def press_use(hand : Hand?)
    @use_revision += 1
    @held_use = nil
    @queued_use = UseRequest.new(hand)
  end

  private def release_use
    @use_revision += 1
    @held_use = nil
    @queued_use = nil
  end

  def use_release_pending? : Bool
    @held_use.nil? && active_use?
  end

  def sync_using_item(hand : Hand?) : Nil
    client.player.using_item = !hand.nil?
    active = @active_use
    if hand
      if active && active.hand == hand
        active.confirm
      else
        @active_use = ActiveUse.new(hand, hand_slot(hand).item_id_int)
      end
    elsif !active || !active.provisional? || active.acknowledged?
      @active_use = nil
    end
  end

  def acknowledge_use(sequence : Int32) : Nil
    return unless (active = @active_use) && (pending = active.sequence)
    return if active.acknowledged? || pending > sequence

    active.acknowledged = true
    active.ticks_left = Math.min(active.ticks_left, PROVISIONAL_USE_ACK_GRACE)
  end

  private def clear_active_use : Nil
    client.player.using_item = false
    @active_use = nil
  end

  private def active_use? : Bool
    !@active_use.nil? || client.player.using_item?
  end

  private def release_using_item
    clear_active_use
    send_packet Serverbound::PlayerAction.new(:finish_using_hand, Vec3i::ORIGIN, :bottom)
  end

  # Activates the "attack" button.
  def start_digging
    return unless client.manual_control.script_write_allowed?("start_digging")
    return if digging?

    self.digging = true
    @attack_queued = true
  end

  # Deactivates the "attack" button.
  def stop_digging
    return unless client.manual_control.script_write_allowed?("stop_digging")
    self.digging = false
  end

  def reset_mining
    self.digging = false
    @attack_queued = false
    @destroy_delay = 0
    @mining_miss_ticks = 0
    @sent_held_item_index = nil
    clear_dig_target
  end

  def reset_use
    release_use
    @manual_use_held = false
    @staged_action_release_pending = false
    clear_active_use
    @use_repeat_delay = 0
    @last_hand_tap_sequence = 0
  end

  # Drops scripted attack and use intent; an active use releases on the next tick.
  def clear_input
    self.digging = false
    @attack_queued = false
    release_use
    @manual_use_held = false
  end

  def queue_staged_action_release : Nil
    @staged_action_release_pending = true
  end

  def apply_manual_input(input : ManualControl::Input)
    @attack_queued = true if input.attack_taps > 0 || (input.attack? && !digging?)
    self.digging = input.attack?

    if input.use?
      hold_use nil
      @manual_use_held = true
    elsif input.use_taps > 0
      press_use nil
      @manual_use_held = false
    elsif @manual_use_held
      release_use
      @manual_use_held = false
    end
  end

  # Ends the previous owner's staged break and active use. Miss, destroy and use
  # cooldowns carry over; only a session reset clears them.
  private def release_staged_actions : Nil
    return unless @staged_action_release_pending

    @staged_action_release_pending = false
    release_using_item if active_use?
    cancel_digging
  end

  def tick
    return unless client.connected?
    tick_held_item
    release_staged_actions
    @use_repeat_delay -= 1 if @use_repeat_delay > 0

    attack_pressed, @attack_queued = @attack_queued, false
    use_pressed, @queued_use = @queued_use, nil
    held = @held_use
    revision = @use_revision
    if active = @active_use
      slot = hand_slot(active.hand)
      if slot.empty? || slot.item_id_int != active.item_id
        clear_active_use
      elsif active.provisional? && (active.ticks_left -= 1) <= 0
        @active_use = nil
      end
    end

    hit = reach_block_or_entity if attack_pressed || use_pressed || digging? || held
    instant_attack = false
    if active_use?
      active_hand = @active_use.try(&.hand)
      wanted = held.try(&.hand)
      release_using_item if !held || (active_hand && wanted && active_hand != wanted)
    else
      instant_attack = start_attack(hit) if attack_pressed
      start_use(use_pressed, hit, revision, hand_tap: held.nil?) if use_pressed && use_continues?(revision)
    end
    if held && @use_repeat_delay == 0 && use_continues?(revision)
      start_use(held, hit, revision, hand_tap: false)
    end
    continue_attack(digging? && !instant_attack, hit)
    @mining_miss_ticks -= 1 if @mining_miss_ticks > 0
  end

  private def tick_held_item
    if @sent_held_item_index != client.player.hotbar_selection
      @sent_held_item_index = client.player.hotbar_selection
      send_packet Serverbound::HeldItemChange.new client.player.hotbar_selection
    end
  end

  # Sends the held-slot sync, if due, and then the swap, each only while
  # *session* is current, no container is open and `authorized` approves under
  # the write lock. The sync cache moves only with a written sync. Returns
  # whether the swap was written.
  def swap_hands(session : Client::PlaySession? = nil, &authorized : -> Bool) : Bool
    guard = -> { client.container_menu.same?(client.inventory_menu) && authorized.call }
    selection = client.player.hotbar_selection
    if @sent_held_item_index != selection
      return false unless client.send_packet_if!(Serverbound::HeldItemChange.new(selection), session, &guard)
      @sent_held_item_index = selection
    end
    client.send_packet_if!(Serverbound::PlayerAction.new(:swap_hands), session, &guard)
  end

  private def start_attack(hit : InteractionHit) : Bool
    return false if @mining_miss_ticks > 0
    if client.player.gamemode == 3
      return true if Client.protocol_version >= 775_u32
      if hit.is_a?(ReachedEntity)
        send_entity_attack(hit.entity)
      elsif !hit || mining_air?(hit)
        register_attack_miss
      end
      send_swing attack: true if Client.protocol_version <= 773_u32
      return false
    end
    return true if piercing_weapon?

    instant_attack = false
    case hit
    when ReachedEntity
      send_entity_attack(hit.entity)
      @destroy_delay = HELD_DESTROY_DELAY if Client.protocol_version >= 777_u32 && client.player.creative_mode?
    when ReachedBlock
      if mining_air?(hit)
        register_attack_miss
      elsif can_mine?
        start_digging(hit)
        instant_attack = mining_air?(hit)
      end
    else
      register_attack_miss
    end
    send_swing attack: true
    instant_attack
  end

  private def send_entity_attack(entity : Entity)
    if Client.protocol_version >= 775_u32
      send_packet Serverbound::Attack.new entity.entity_id
    else
      send_packet Serverbound::InteractEntity.new entity.entity_id, :attack, sneaking: client.player.sneaking?
    end
  end

  private def register_attack_miss
    @mining_miss_ticks = MINING_MISS_DELAY unless client.player.gamemode == 1
  end

  private def continue_attack(down : Bool, hit : InteractionHit)
    @mining_miss_ticks = 0 unless down
    return if @mining_miss_ticks > 0 || active_use? || piercing_weapon?

    if down && hit.is_a?(ReachedBlock)
      return if mining_air?(hit) || !can_mine?
      continue_digging(hit)
    else
      cancel_digging
    end
  end

  private def continue_digging(reached : ReachedBlock)
    if @destroy_delay > 0
      @destroy_delay -= 1
      send_swing attack: true
      return
    end

    active = @digging_block
    if client.player.creative_mode? || !active || !same_dig_target?(reached)
      send_swing(attack: true) if start_digging(reached)
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

  private def start_use(request : UseRequest, hit : InteractionHit, revision : UInt64, *, hand_tap : Bool)
    return if @digging_block

    @use_repeat_delay = HELD_USE_DELAY
    return if hit.is_a?(ReachedBlock) && client.dimension.world_border.outside?(hit.block)

    if hand = request.hand
      route_use(hand, hit, revision, hand_tap: hand_tap)
    elsif route_use(:main_hand, hit, revision, hand_tap: hand_tap) && use_continues?(revision)
      route_use(:off_hand, hit, revision, hand_tap: hand_tap)
    end
  end

  # Callbacks during a send may stop, reset or replace the press being routed.
  private def use_current?(revision : UInt64) : Bool
    @use_revision == revision
  end

  private def allocate_use_sequence(location : Vec3i, operation : Symbol, hand_tap : Bool) : Int32
    sequence = client.next_sequence
    client.pending_block_operations[sequence] = BlockOperation.new(location, operation)
    @last_hand_tap_sequence = Math.max(@last_hand_tap_sequence, sequence) if hand_tap
    sequence
  end

  private def send_use_item(hand : Hand, slot : Slot, hand_tap : Bool) : ItemUseRules::Result
    decision = if client.item_on_cooldown?(slot)
                 ItemUseRules::Decision.new(ItemUseRules::Result::Pass)
               else
                 ItemUseRules.evaluate(client.player, slot)
               end
    sequence = allocate_use_sequence(Vec3i::ORIGIN, :use, hand_tap)
    starts_use = decision.result.unknown? ? starts_consuming?(slot) : decision.starts_sustained_use?
    if starts_use
      @active_use = ActiveUse.new(hand, slot.item_id_int, sequence, PROVISIONAL_USE_TICKS)
    end
    send_packet Serverbound::UseItem.new hand, sequence, client.player.look.yaw, client.player.look.pitch
    decision.result
  end

  private def hand_slot(hand : Hand)
    hand.main_hand? ? inventory.main_hand : inventory.off_hand
  end

  private def starts_consuming?(slot : Slot) : Bool
    return false if slot.empty? || client.player.gamemode == 3
    return false if slot.components_to_remove.includes?("consumable") || slot.components_to_add.has_key?("use_cooldown")
    return false unless (name = held_item_name(slot)) && slot.edible?
    return false if name == "chorus_fruit" && !slot.components_to_remove.includes?("use_cooldown")

    consumable = slot.components_to_add["consumable"]?
    if consumable.is_a?(DataComponents::Consumable)
      return false unless consumable.consume_seconds * 20_f32 >= 1_f32
    end

    return true if client.player.invulnerable? || client.player.food < 20
    food = slot.components_to_add["food"]?
    return food.can_always_eat? if food.is_a?(DataComponents::Food)
    return true if slot.components_to_remove.includes?("food")

    {"golden_apple", "enchanted_golden_apple", "honey_bottle", "suspicious_stew", "chorus_fruit"}.includes?(name)
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

    case held_item_name(slot)
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

  # Suppress UseItem fall-through when vanilla consumes the block interaction.
  # Unknown/unloaded block states do not consume.
  private def block_use_consumes_click?(reached : ReachedBlock, hand : Hand) : Bool
    block_state = client.dimension.interaction_block_state(reached.block)
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
    name = held_item_name(hand_slot(hand))
    return true if {"water_bucket", "lava_bucket", "powder_snow_bucket"}.includes?(name)
    return false unless name == "bucket"

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
    case client.player.gamemode
    when 0, 1 then true
    when 2    then held.components_to_add.has_key?("can_break")
    else           false
    end
  end

  private def piercing_weapon? : Bool
    held = inventory.main_hand
    return false if held.empty?
    return true if held.components_to_add.has_key?("piercing_weapon")

    Client.protocol_version >= 774_u32 && !held.components_to_remove.includes?("piercing_weapon") &&
      !!held_item_name(held).try(&.ends_with?("_spear"))
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

  private def reach_block_or_entity : ReachedBlock | ReachedEntity | Nil
    player = client.player
    eyes = player.eyes
    block_range = player.block_interaction_range
    entity_range = player.entity_interaction_range
    trace_range = Math.max(block_range, entity_range)
    return if trace_range.zero?

    look = player.look.to_vec3
    block_hit = reach_block_along(eyes, look * trace_range)
    block_distance_sq = block_hit ? eyes.dist_sq(block_hit.intercept) : trace_range ** 2
    entity_hit = reach_entity_along(eyes, look * Math.sqrt(block_distance_sq), block_distance_sq)

    if entity_hit && (distance_sq = eyes.dist_sq(entity_hit.intercept)) < block_distance_sq
      entity_hit if distance_sq < entity_range ** 2
    elsif block_hit && block_distance_sq < block_range ** 2
      block_hit
    end
  end

  private def reach_entity_along(eyes : Vec3d, reach : Vec3d, nearest : Float64) : ReachedEntity?
    player_id = client.player.entity_id.to_u32
    entities = client.dimension.entities
    player_box = client.player.aabb
    search = AABBd.containing_all(player_box, player_box.offset(reach)).grow(1.0, 1.0, 1.0)
    vehicles = interaction_vehicles(player_id)
    player_root = vehicles ? interaction_root_vehicle(player_id, vehicles) : player_id
    hit = nil

    entities.each_value do |entity|
      next if entity.entity_id == player_id || !entity.pickable?
      next if client.player_list[entity.uuid]?.try(&.gamemode) == 3 && entity.metadata.try(&.name) == "player"
      box = entity.bounding_box
      next unless search.intersects?(box)

      if (box.min.x <= eyes.x < box.max.x) &&
         (box.min.y <= eyes.y < box.max.y) &&
         (box.min.z <= eyes.z < box.max.z)
        hit = ReachedEntity.new(entity, eyes)
        return hit if entity.passenger_ids.includes?(player_id)
        nearest = 0.0
      elsif intercept = entity_intercept(eyes, reach, box)
        distance_sq = eyes.dist_sq(intercept)
        # ProjectileUtil treats zero as a sentinel when scanning later candidates.
        next unless distance_sq < nearest || nearest.zero?
        if vehicles && interaction_root_vehicle(entity.entity_id, vehicles) == player_root
          next unless nearest.zero?
        else
          nearest = distance_sq
        end
        hit = ReachedEntity.new(entity, intercept)
      end
    end
    hit
  end

  private def interaction_vehicles(player_id : UInt32) : Hash(UInt32, UInt32)?
    entities = client.dimension.entities
    return unless entities.each_value.any?(&.passenger_ids.includes?(player_id))

    vehicles = {} of UInt32 => UInt32
    entities.each_value do |entity|
      entity.passenger_ids.each { |passenger| vehicles[passenger] = entity.entity_id }
    end
    vehicles
  end

  private def interaction_root_vehicle(id : UInt32, vehicles : Hash(UInt32, UInt32)) : UInt32
    vehicles.size.times do
      id = vehicles[id]? || return id
    end
    id
  end

  private def entity_intercept(eyes : Vec3d, reach : Vec3d, box : AABBd) : Vec3d?
    epsilon = 1e-7
    nearest = 1.0
    hit = nil
    3.times do |axis|
      delta = reach[axis]
      next if delta.abs <= epsilon
      plane = delta > 0 ? box.min[axis] : box.max[axis]
      scalar = (plane - eyes[axis]) / delta
      next unless 0.0 < scalar < nearest

      point = eyes + reach * scalar
      u = (axis + 1) % 3
      v = (axis + 2) % 3
      next unless (box.min[u] - epsilon < point[u] < box.max[u] + epsilon) &&
                  (box.min[v] - epsilon < point[v] < box.max[v] + epsilon)
      nearest = scalar
      hit = point
    end
    hit
  end

  # Like vanilla's BlockGetter.clip: visits the cells the ray passes through in
  # order and returns the first whose outline is hit. A cell owns its outline even
  # where it extends outside the cell (piston arms, offset plants).
  private def reach_block_along(start : Vec3d, reach : Vec3d) : ReachedBlock?
    mcdata = MCData.default
    held = inventory.main_hand
    held_id = held.item_id_int unless held.empty?
    each_traversed_cell(start, reach) do |cell_x, cell_y, cell_z|
      next unless block_state = client.dimension.interaction_block_state(cell_x, cell_y, cell_z)
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
