require "../client"
require "../world/look"
require "../world/vec3"
require "./physics"

class Rosegold::Interactions
  private class ReachedBlock
    getter intercept : Vec3d, block : Vec3i, face : BlockFace

    def initialize(@intercept, @block, @face); end
  end

  @using_hand = nil
  @queue_using_hand = nil
  @using_hand_delay = 0_i32
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

  # Activates the "use" button.
  def start_using_hand(hand : Hand = :main_hand) # TODO: Auto select hand each tick
    @using_hand = hand
    @queue_using_hand = hand
  end

  # Deactivates the "use" button.
  def stop_using_hand
    return unless @using_hand

    @using_hand = nil
    # TODO: seems to be only for eating
    # move to tick loop

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
    return if @using_hand_delay > 0

    if using_hand = @using_hand || @queue_using_hand
      @using_hand_delay = using_hand_delay_for inventory.main_hand
      @queue_using_hand = nil
      case reached = reach_block_or_entity
      when Entity
        Log.warn { "Rosegold does not support using items on entities yet" }
      when ReachedBlock
        place_block using_hand, reached

        # Generate sequence number for MC 1.21+
        sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

        # Track pending operation
        if client.protocol_version >= 767_u32
          operation = BlockOperation.new(Vec3i::ORIGIN, :use) # Use operations don't target specific blocks
          client.pending_block_operations[sequence] = operation
        end

        send_packet Serverbound::UseItem.new using_hand, sequence, client.player.look.yaw, client.player.look.pitch
      else
        # Generate sequence number for MC 1.21+
        sequence = client.protocol_version >= 767_u32 ? client.next_sequence : 0

        # Track pending operation
        if client.protocol_version >= 767_u32
          operation = BlockOperation.new(Vec3i::ORIGIN, :use) # Use operations don't target specific blocks
          client.pending_block_operations[sequence] = operation
        end

        send_packet Serverbound::UseItem.new using_hand, sequence, client.player.look.yaw, client.player.look.pitch
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

  private def place_block(hand : Hand, reached : ReachedBlock)
    cursor = (reached.intercept - reached.block.to_f64).to_f32
    inside_block = false # TODO

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

    # Reset digging state
    @digging_block = nil
    self.digging = false

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

  private def reach_block_or_entity : ReachedBlock? | Rosegold::Entity?
    reach_block_or_entity_unified
  end

  private def reach_block : ReachedBlock?
    eyes = client.player.eyes
    boxes = get_block_hitboxes(eyes, reach_vec)
    Raytrace.raytrace(eyes, reach_vec, boxes).try do |reached|
      block = boxes[reached.box_nr].min.block
      ReachedBlock.new reached.intercept, block, reached.face
    end
  end

  private def reach_entity : Rosegold::Entity?
    client.dimension.raycast_entity client.player.eyes, reach_vec, reach_length
  end

  # Unified raytracing that properly handles both entities and blocks
  # ensuring entities cannot be hit through blocks
  private def reach_block_or_entity_unified : ReachedBlock? | Rosegold::Entity?
    eyes = client.player.eyes
    reach_vector = reach_vec

    # Get all block collision boxes
    block_boxes = get_block_hitboxes(eyes, reach_vector)

    # Get all entity bounding boxes for living entities within reach
    entity_boxes = [] of AABBd
    entity_map = [] of Rosegold::Entity

    reach_aabb = AABBd.new(eyes, eyes + reach_vector)
    client.dimension.entities.each_value do |entity|
      next unless entity.living?

      entity_bounding_box = entity.bounding_box
      # Only include entities that could potentially be hit
      if reach_aabb.intersects?(entity_bounding_box)
        entity_boxes << entity_bounding_box
        entity_map << entity
      end
    end

    # Combine all boxes for unified raytracing
    all_boxes = block_boxes + entity_boxes
    block_count = block_boxes.size

    # Perform unified raytracing
    result = Raytrace.raytrace(eyes, reach_vector, all_boxes)
    return nil unless result

    # Determine if we hit a block or entity based on box index
    if result.box_nr < block_count
      # Hit a block
      block = block_boxes[result.box_nr].min.block
      ReachedBlock.new result.intercept, block, result.face
    else
      # Hit an entity
      entity_index = result.box_nr - block_count
      entity_map[entity_index]
    end
  end

  private def reach_length
    client.player.gamemode == 1 ? 5.0 : 4.5
  end

  private def reach_vec
    client.player.look.to_vec3 * reach_length
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
        block_shape.map &.to_f64.offset(x, y, z)
      end || Array(AABBd).new 0 # outside world or outside loaded chunks - XXX make solid so we don't fall through unloaded chunks
    end
  end

  private def inventory : Inventory
    @inventory ||= Inventory.new client
  end
end
