require "../client"
require "../world/look"
require "../world/vec3"
require "./physics"

# Vanilla InteractionResult enum for client-side interaction prediction
enum InteractionResult
  SUCCESS
  CONSUME
  CONSUME_PARTIAL
  PASS
  FAIL

  def consumes_action?
    case self
    when SUCCESS, CONSUME, CONSUME_PARTIAL
      true
    else
      false
    end
  end
end

class Rosegold::Interactions
  private class ReachedBlock
    getter intercept : Vec3d, block : Vec3i, face : BlockFace, inside : Bool

    def initialize(@intercept, @block, @face, @inside = false); end
  end

  @using_hand : Hand? = nil
  @queue_using_hand : Bool = false
  @using_hand_delay = 0_i32
  @right_click_delay = 0_i32
  @digging_block : ReachedBlock?
  @dig_hand_swing_countdown = 0_i8
  @attack_queued = false
  @digging = false
  @block_damage_progress = 0_f32
  @last_tick_held_item : Slot = Slot.new
  @sent_held_item_index : UInt32?

  getter client : Client
  property? digging : Bool = false

  def initialize(@client)
  end

  # Activates the "use" button. Vanilla tries both hands in order.
  def start_using_hand
    @queue_using_hand = true
  end

  # Deactivates the "use" button. Sends RELEASE_USE_ITEM for all continuous use items.
  def stop_using_hand
    return unless @using_hand

    @using_hand = nil

    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(Vec3i::ORIGIN, :use) # Use operations don't target specific blocks
      client.pending_block_operations[sequence] = operation
    end

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
  end

  def tick
    return unless client.connected?
    tick_held_item
    tick_attack
    tick_digging
    tick_using_hand
    @last_tick_held_item = inventory.main_hand
  end

  private def inventory
    Inventory.new client
  end

  private def tick_held_item
    if @sent_held_item_index != client.player.hotbar_selection
      @sent_held_item_index = client.player.hotbar_selection
      send_packet Serverbound::HeldItemChange.new client.player.hotbar_selection
    end
  end

  private def tick_attack
    return unless @attack_queued

    @attack_queued = false

    case reached = reach_block_or_entity
    when Entity
      send_packet Serverbound::InteractEntity.new reached.entity_id, :attack
      send_packet Serverbound::SwingArm.new
    when ReachedBlock
      start_digging reached
    end
  end

  private def tick_digging
    reached = reach_block_or_entity
    if @digging_block
      if !digging?
        cancel_digging
        return
      end

      case reached
      when Entity
        # do nothing, but retain @block_damage_progress like vanilla client
      when ReachedBlock
        tick_digging_block reached
      when nil
        cancel_digging
      end
    else
      return unless digging?

      if reached.is_a? ReachedBlock
        start_digging reached
      end
    end
  end

  private def tick_digging_block(reached)
    if digging_block = @digging_block
      if reached.block != digging_block.block
        cancel_digging
      end

      if @last_tick_held_item != inventory.main_hand
        cancel_digging
        return
      end

      client.dimension.block_state(digging_block.block).try do |block_state|
        block = Block.from_block_state_id block_state
        @block_damage_progress += block.break_damage inventory.main_hand, client.player
      end

      if @block_damage_progress >= 1.0
        finish_digging
        @block_damage_progress = 0.0
      end

      @dig_hand_swing_countdown -= 1
      if @dig_hand_swing_countdown <= 0
        @dig_hand_swing_countdown = 6
        send_packet Serverbound::SwingArm.new
      end
    end
  end

  private def tick_using_hand
    @using_hand_delay -= 1 if @using_hand_delay > 0
    @right_click_delay -= 1 if @right_click_delay > 0
    return if @using_hand_delay > 0
    return if @right_click_delay > 0

    if @queue_using_hand || @using_hand
      @right_click_delay = 4 # Vanilla 4-tick right-click delay
      @queue_using_hand = false

      # Try both hands like vanilla (main hand, then off hand)
      [Hand::MainHand, Hand::OffHand].each do |hand|
        success = try_use_hand(hand)
        if success
          @using_hand = hand
          break
        end
      end
    end
  end

  # Vanilla-style interaction per hand: entity -> block -> air
  private def try_use_hand(hand : Hand) : Bool
    return false if player_is_using_item?

    case reached = reach_block_or_entity(hand)
    when Entity
      Log.debug { "Interacting with entity: #{reached.entity_id}" }
      result = interact_with_entity hand, reached
      if result
        @using_hand_delay = using_hand_delay_for inventory.main_hand
        return true
      end
      # Fall through to block interaction if entity interaction failed
    when ReachedBlock
      Log.debug { "Reached block: #{reached.block} at #{reached.intercept} face #{reached.face}" }
      result = try_block_interaction hand, reached
      if result
        @using_hand_delay = using_hand_delay_for inventory.main_hand
        return true
      end
      # Fall through to item use if block interaction failed
    end

    # Try using item in air (vanilla fallback)
    Log.debug { "Using item in air" }
    result = try_item_use hand
    if result
      @using_hand_delay = using_hand_delay_for inventory.main_hand
      return true
    end

    false
  end

  private def player_is_using_item? : Bool
    # Check if player is already using an item (eating, drinking, blocking, etc.)
    @using_hand != nil && @using_hand_delay > 0
  end

  private def try_block_interaction(hand : Hand, reached : ReachedBlock) : Bool
    place_block hand, reached

    # Only send UseItem if block placement might have failed
    # (vanilla sends UseItem as fallback for block interactions)
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(Vec3i::ORIGIN, :use)
      client.pending_block_operations[sequence] = operation
    end
    send_packet Serverbound::UseItem.new hand, sequence, client.player.look.yaw, client.player.look.pitch
    true
  end

  private def try_item_use(hand : Hand) : Bool
    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(Vec3i::ORIGIN, :use)
      client.pending_block_operations[sequence] = operation
    end

    send_packet Serverbound::UseItem.new hand, sequence, client.player.look.yaw, client.player.look.pitch
    true
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

  private def place_block(hand : Hand, reached : ReachedBlock)
    cursor = (reached.intercept - reached.block.to_f64).to_f32
    inside_block = reached.inside

    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(reached.block, :place)
      client.pending_block_operations[sequence] = operation
    end

    send_packet Serverbound::PlayerBlockPlacement.new \
      hand, reached.block, reached.face, cursor, inside_block, sequence
    send_packet Serverbound::SwingArm.new hand
  end

  private def start_digging(reached : ReachedBlock)
    @digging_block = reached
    @dig_hand_swing_countdown = 6

    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(reached.block, :dig)
      client.pending_block_operations[sequence] = operation
    end

    send_packet Serverbound::PlayerAction.new \
      :start, reached.block, reached.face, sequence
    send_packet Serverbound::SwingArm.new
  end

  private def finish_digging
    reached = @digging_block
    return unless reached

    # Reset digging block but keep digging state for continuous digging
    @digging_block = nil
    # Don't set self.digging = false here to allow continuous digging

    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(reached.block, :dig)
      client.pending_block_operations[sequence] = operation
    end

    send_packet Serverbound::PlayerAction.new \
      :finish, reached.block, reached.face, sequence
  end

  private def cancel_digging
    reached = @digging_block
    return unless reached
    @digging_block = nil
    @block_damage_progress = 0.0

    # Generate sequence number for MC 1.21+
    sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

    # Track pending operation
    if client.protocol_version >= 767_u32
      operation = BlockOperation.new(reached.block, :dig)
      client.pending_block_operations[sequence] = operation
    end

    send_packet Serverbound::PlayerAction.new \
      :cancel, reached.block, reached.face, sequence
  end

  private def reach_block_or_entity(hand : Hand = Hand::MainHand) : ReachedBlock? | Rosegold::Entity?
    reach_block_or_entity_unified(hand)
  end

  private def reach_block : ReachedBlock?
    eyes = client.player.eyes
    boxes = get_block_hitboxes(eyes, reach_vec)
    Raytrace.raytrace(eyes, reach_vec, boxes).try do |reached|
      block = boxes[reached.box_nr].min.block
      inside = is_inside_block(reached.intercept, block)
      ReachedBlock.new reached.intercept, block, reached.face, inside
    end
  end

  private def reach_entity : Rosegold::Entity?
    client.dimension.raycast_entity client.player.eyes, reach_vec, reach_length
  end

  # Vanilla-style unified raytracing with separate block/entity reach distances
  private def reach_block_or_entity_unified(hand : Hand) : ReachedBlock? | Rosegold::Entity?
    eyes = client.player.eyes
    block_reach = block_interaction_range
    entity_reach = entity_interaction_range
    max_reach = Math.max(block_reach, entity_reach)

    # Use max reach for raytracing, filter by appropriate distance later
    reach_vector = client.player.look.to_vec3 * max_reach

    # Get block raytracing result
    block_boxes = get_block_hitboxes(eyes, reach_vector)
    block_result = Raytrace.raytrace(eyes, reach_vector, block_boxes)

    # Get entity raytracing result
    entity_result = nil
    closest_entity_distance = Float64::INFINITY
    closest_entity = nil

    reach_aabb = AABBd.new(eyes, eyes + reach_vector)
    client.dimension.entities.each_value do |entity|
      next unless entity.living? || entity.interactable?

      entity_box = entity.bounding_box
      next unless reach_aabb.intersects?(entity_box)

      # Raytrace against this entity
      entity_ray_result = Raytrace.raytrace(eyes, reach_vector, [entity_box])
      next unless entity_ray_result

      distance = (entity_ray_result.intercept - eyes).length
      if distance < closest_entity_distance && distance <= entity_reach
        closest_entity_distance = distance
        closest_entity = entity
        entity_result = entity_ray_result
      end
    end

    # Return closest hit, but respect reach distances
    block_distance = block_result ? (block_result.intercept - eyes).length : Float64::INFINITY
    entity_distance = entity_result ? closest_entity_distance : Float64::INFINITY

    # Filter by reach distances and return closest valid hit
    valid_block = block_result && block_distance <= block_reach
    valid_entity = entity_result && closest_entity && entity_distance <= entity_reach

    if valid_block && valid_entity
      # Both valid, return closest
      if block_distance < entity_distance
        if br = block_result
          block = block_boxes[br.box_nr].min.block
          inside = is_inside_block(br.intercept, block)
          ReachedBlock.new br.intercept, block, br.face, inside
        else
          closest_entity
        end
      else
        closest_entity
      end
    elsif valid_block
      if br = block_result
        block = block_boxes[br.box_nr].min.block
        inside = is_inside_block(br.intercept, block)
        ReachedBlock.new br.intercept, block, br.face, inside
      else
        nil
      end
    elsif valid_entity
      closest_entity
    else
      nil
    end
  end

  # Vanilla reach distances
  private def block_interaction_range
    client.player.gamemode == 1 ? 5.0 : 4.5
  end

  private def entity_interaction_range
    client.player.gamemode == 1 ? 5.0 : 3.0
  end

  # Returns all block collision boxes that may intersect from `start` towards `reach`.
  private def get_block_hitboxes(start : Vec3d, reach : Vec3d) : Array(AABBd)
    bounds = AABBd.new(start, start + reach)
    # fences are 1.5m tall
    min_block = bounds.min.down(0.5).block
    max_block = bounds.max.block
    blocks_coords = Indexable.cartesian_product({
      (min_block.x..max_block.x).to_a,
      (min_block.y..max_block.y).to_a,
      (min_block.z..max_block.z).to_a,
    })
    blocks_coords.flat_map do |block_coords|
      x, y, z = block_coords
      client.dimension.block_state(x, y, z).try do |block_state|
        block_shape = MCData::DEFAULT.block_state_collision_shapes[block_state]

        # If no collision shapes, check if it's an interactive block and use interaction hitbox
        if block_shape.empty?
          interaction_shape = get_interaction_hitbox(block_state, x, y, z)
          if interaction_shape
            [interaction_shape]
          else
            Array(AABBd).new 0
          end
        else
          block_shape.map &.to_f64.offset(x, y, z)
        end
      end || Array(AABBd).new 0 # outside world or outside loaded chunks - XXX make solid so we don't fall through unloaded chunks
    end
  end

  # Returns interaction hitbox for blocks that have no collision shapes but can be interacted with
  private def get_interaction_hitbox(block_state : UInt16, x : Int32, y : Int32, z : Int32) : AABBd?
    block = Block.from_block_state_id(block_state)
    case block.id_str
    when .includes?("button")
      # Buttons have a small hitbox depending on their face
      # For floor buttons (face=floor), use a small hitbox on top of the block
      if MCData::DEFAULT.block_state_names[block_state].includes?("face=floor")
        # Floor button: small hitbox on top surface
        AABBd.new(
          x + 0.3125, y + 0.0, z + 0.3125,   # min corner
          x + 0.6875, y + 0.0625, z + 0.6875 # max corner
        )
      elsif MCData::DEFAULT.block_state_names[block_state].includes?("face=wall")
        # Wall button: determine which wall and create appropriate hitbox
        block_state_name = MCData::DEFAULT.block_state_names[block_state]
        if block_state_name.includes?("facing=north")
          AABBd.new(x + 0.3125, y + 0.375, z + 0.875, x + 0.6875, y + 0.625, z + 1.0)
        elsif block_state_name.includes?("facing=south")
          AABBd.new(x + 0.3125, y + 0.375, z + 0.0, x + 0.6875, y + 0.625, z + 0.125)
        elsif block_state_name.includes?("facing=east")
          AABBd.new(x + 0.0, y + 0.375, z + 0.3125, x + 0.125, y + 0.625, z + 0.6875)
        elsif block_state_name.includes?("facing=west")
          AABBd.new(x + 0.875, y + 0.375, z + 0.3125, x + 1.0, y + 0.625, z + 0.6875)
        else
          # Default wall button hitbox
          AABBd.new(x + 0.3125, y + 0.375, z + 0.3125, x + 0.6875, y + 0.625, z + 0.6875)
        end
      elsif MCData::DEFAULT.block_state_names[block_state].includes?("face=ceiling")
        # Ceiling button: small hitbox on bottom surface
        AABBd.new(
          x + 0.3125, y + 0.9375, z + 0.3125, # min corner
          x + 0.6875, y + 1.0, z + 0.6875     # max corner
        )
      else
        # Default button hitbox (floor)
        AABBd.new(
          x + 0.3125, y + 0.0, z + 0.3125,
          x + 0.6875, y + 0.0625, z + 0.6875
        )
      end
    else
      # No interaction hitbox for this block type
      nil
    end
  end

  private def interact_with_entity(hand : Hand, entity : Rosegold::Entity) : Bool
    # Get the exact hit location from raytracing for proper relative positioning
    eyes = client.player.eyes
    reach_vector = client.player.look.to_vec3 * entity_interaction_range
    entity_box = entity.bounding_box

    # Get precise hit location on entity
    ray_result = Raytrace.raytrace(eyes, reach_vector, [entity_box])
    hit_location = ray_result ? ray_result.intercept : eyes + reach_vector.normed * (entity.position - eyes).length

    # Calculate interaction position relative to entity
    relative_pos = hit_location - entity.position

    # Try InteractAt first (vanilla behavior)
    send_packet Serverbound::InteractEntity.new(
      entity.entity_id,
      Serverbound::InteractEntity::Action::InteractAt,
      relative_pos.x.to_f32,
      relative_pos.y.to_f32,
      relative_pos.z.to_f32,
      hand,
      client.player.sneaking?
    )

    # Vanilla client-side prediction of InteractAt result
    interact_at_result = predict_entity_interact_at_result(entity, hand)

    # Only send fallback Interact if InteractAt didn't consume the action
    unless interact_at_result.consumes_action?
      send_packet Serverbound::InteractEntity.new(
        entity.entity_id,
        Serverbound::InteractEntity::Action::Interact,
        hand: hand,
        sneaking: client.player.sneaking?
      )
    end

    # Send arm swing for visual feedback
    send_packet Serverbound::SwingArm.new(hand)

    # Return success based on interaction result
    interact_at_result.consumes_action? || predict_entity_interact_result(entity, hand).consumes_action?
  end

  # Predict InteractAt result based on entity type and state (vanilla client-side logic)
  private def predict_entity_interact_at_result(entity : Rosegold::Entity, hand : Hand) : InteractionResult
    # Most entities don't consume InteractAt - they pass through to regular interact
    # Only specific cases like armor stands, item frames, etc. consume InteractAt

    case entity.metadata.try(&.name)
    when "armor_stand"
      InteractionResult::SUCCESS
    when "item_frame"
      InteractionResult::SUCCESS
    when "glow_item_frame"
      InteractionResult::SUCCESS
    else
      InteractionResult::PASS
    end
  end

  # Predict regular Interact result based on entity type and held item (vanilla client-side logic)
  private def predict_entity_interact_result(entity : Rosegold::Entity, hand : Hand) : InteractionResult
    held_item = hand == Hand::MainHand ? inventory.main_hand : inventory.off_hand

    # Basic interaction success prediction
    if entity.living?
      # Living entities typically have some form of interaction
      case held_item.item_id_int
      when 0 # Empty hand - basic interaction
        InteractionResult::SUCCESS
      else
        # Item-specific interactions (feeding, etc.)
        InteractionResult::SUCCESS
      end
    else
      # Non-living entities (boats, minecarts, etc.)
      InteractionResult::SUCCESS
    end
  end

  # Check if hit intercept is inside the block bounds (vanilla inside_block calculation)
  private def is_inside_block(intercept : Vec3d, block : Vec3i) : Bool
    # Convert intercept to relative position within the block
    relative_pos = intercept - block.to_f64

    # Check if the hit point is inside the block bounds [0,1]
    relative_pos.x > 0.0 && relative_pos.x < 1.0 &&
      relative_pos.y > 0.0 && relative_pos.y < 1.0 &&
      relative_pos.z > 0.0 && relative_pos.z < 1.0
  end

  private def inventory : Inventory
    @inventory ||= Inventory.new client
  end
end
