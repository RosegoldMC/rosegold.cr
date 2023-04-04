require "../rosegold"
require "./control/action"

class Rosegold::Bot
  private getter client : Client

  getter inventory : Inventory

  def initialize(@client)
    @inventory = Inventory.new client
  end

  delegate health, food, saturation, gamemode, to: client.player

  # Revive the player if dead. Does nothing if alive.
  def respawn
    raise "Not implemented" # TODO send packet
  end

  # Send a message or slash command.
  def chat(message : String)
    client.queue_packet Serverbound::Chat.new message
  end

  # Is adjusted to server TPS.
  def wait_ticks(ticks : UInt32)
    sleep ticks / 20 # TODO adjust to server TPS, changing over time
  end

  def wait_tick
    wait_ticks 1
  end

  # Direction the player is looking.
  def look
    client.player.look
  end

  # Waits for the new look to be sent to the server.
  def look=(look : Look)
    client.physics.look = look
  end

  # Waits for the new look to be sent to the server.
  def look=(vec : Vec3d)
    client.physics.look = vec
  end

  # Computes the new look from the current look.
  # Waits for the new look to be sent to the server.
  def look(&block : Look -> Look)
    client.physics.look = block.call look
  end

  # Sets the yaw of the look
  # Waits for the new look to be sent to the server
  def yaw=(yaw : Float64)
    self.look = look.with_yaw yaw
  end

  # Sets the pitch of the look
  # Waits for the new look to be sent to the server
  def pitch=(pitch : Float64)
    self.look = look.with_pitch pitch
  end

  def yaw
    look.yaw
  end

  def pitch
    look.pitch
  end

  # Waits for the new look to be sent to the server.
  def look_at(location : Vec3d)
    client.physics.look = Look.from_vec location - eyes
  end

  # Waits for the new look to be sent to the server.
  def look_at_horizontal(location : Vec3d)
    look_at location.with_y eyes.y
  end

  # Location of the player's feet.
  # To change the location, use #move_to.
  def feet
    client.player.feet
  end

  # Location of the player's eyes.
  # To change the location, use #move_to.
  def eyes
    client.player.eyes
  end

  # Location of the player's feet.
  # To change the location, use #move_to.
  def feet
    client.player.feet
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  def move_to(location : Vec3d)
    client.physics.move location
  end

  # Moves straight towards `location`.
  # Waits for arrival.
  def move_to(x : Float64, z : Float64)
    client.physics.move Vec3d.new x, feet.y, z
  end

  # Computes the destination location from the current feet location.
  # Moves straight towards the destination.
  # Waits for arrival.
  def move_to(&block : Vec3d -> Vec3d)
    client.physics.move block.call feet
  end

  # Stop moving towards the target specified in #move_to
  # Dequeue any jump queued with #start_jump
  def stop_moving
    client.physics.move = nil
    client.physics.jump_queued = false
  end

  # Jumps the next time the player is on the ground.
  def start_jump
    client.physics.jump_queued = true
  end

  # Use #interact_block to enter a bed.
  def leave_bed
    client.connection.send_packet Serverbound::EntityAction.new \
      client.player.entity_id, Serverbound::EntityAction::Type::LeaveBed
  end

  # TODO select interact/placement location/entity by raytracing; if location is passed, just look there, but interact with whatever may be in the way

  def interact_block(look_location : Vec3d? = nil)
    reached = reach_block_or_entity
    return unless reached
    intercept, location, face = reached
    cursor = (intercept - location).to_f32
    hand = Hand::MainHand # TODO
    inside_block = false  # TODO
    client.connection.send_packet Serverbound::PlayerBlockPlacement.new \
      location, face, cursor, hand, inside_block
    client.connection.send_packet Serverbound::SwingArm.new hand
  end

  # Raises an error if the hand slot is not updated within `timeout_ticks`.
  def place_block_against(look_location : Vec3d? = nil, timeout_ticks = 0)
    interact_block(look_location)
    # TODO raise an error if the hand slot is not updated within `timeout_ticks`
  end

  # The active (main hand) hotbar slot number (1-9).
  def hotbar_selection
    client.player.hotbar_selection + 1
  end

  # Selects the active (main hand) hotbar slot number (1-9).
  def hotbar_selection=(index : UInt8)
    # TODO check range
    client.queue_packet Serverbound::HeldItemChange.new index - 1
    client.player.hotbar_selection = index - 1
  end

  def swap_hands
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::SwapHands, Vec3i.ORIGIN, 0
  end

  def drop_hand_single
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::DropHandSingle, Vec3i.ORIGIN, 0
    client.connection.send_packet Serverbound::SwingArm.new
  end

  def drop_hand_full
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::DropHandFull, Vec3i.ORIGIN, 0
    client.connection.send_packet Serverbound::SwingArm.new
  end

  # Moves the slot to the hotbar and selects it.
  # This is faster and less error-prone than moving slots around individually.
  def pick_slot(slot_nr : UInt16)
    client.connection.send_packet Serverbound::PickItem.new slot_nr
  end

  def start_using_item(hand = Hand::MainHand)
    client.connection.send_packet Serverbound::UseItem.new hand
    client.connection.send_packet Serverbound::SwingArm.new
  end

  def stop_using_item
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::FinishUsingHand, Vec3i.ORIGIN, 0
  end

  # not exposed, for rules compliance
  @dig_action : Action(Tuple(Vec3i, BlockFace))?
  @dig_hand_swing_countdown = 0_i8

  # waits for completion, throws error if cancelled
  def dig(ticks : UInt32, look_location : Vec3d)
    action = start_digging(look_location)
    wait_ticks ticks
    finish_digging
    action.join
  end

  # cancels any ongoing dig action
  def start_digging(look_location : Vec3d = player.look)
    cancel_digging if @dig_action
    @dig_action.try { |action| raise "Already digging #{action.target}" }
    look_at look_location if look_location
    @dig_action.try { |action| raise "Already digging #{action.target}" }

    reached = reach_block_or_entity
    unless reached
      dig_action = Action.new({Vec3d::ORIGIN, 0}).tap &.succeed
      return dig_action
    end
    _intercept, location, face = reached

    dig_action = @dig_action = Action.new({location, face})
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::Start, location, face
    client.connection.send_packet Serverbound::SwingArm.new
    @dig_hand_swing_countdown = 6
    dig_action
  end

  def finish_digging
    dig_action = @dig_action
    return unless dig_action
    location, face = dig_action.target
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::Finish, location, face
    @dig_action = nil
    dig_action.succeed
  end

  def cancel_digging
    dig_action = @dig_action
    return unless dig_action
    location, face = dig_action.target
    client.connection.send_packet Serverbound::PlayerDigging.new \
      Serverbound::PlayerDigging::Status::Finish, location.block, face
    @dig_action = nil
    dig_action.fail "Cancelled"
  end

  # Add a callback processed upon specified incoming packet
  #
  # ```
  # client.on_packet Clientbound::Chat do |chat|
  #   puts "Received chat: #{chat.message}"
  # end
  # ```
  def on(packet_type : T.class, &block : T ->) forall T
    client.on packet_type, &block
  end

  private def on_physics_tick
    if @digging_location
      @dig_hand_swing_countdown -= 1
      if @dig_hand_swing_countdown <= 0
        @dig_hand_swing_countdown = 6
        client.connection.send_packet Serverbound::SwingArm.new
      end
    end
  end

  private def reach_block_or_entity(look_location : Vec3d? = nil)
    look_at look_location if look_location
    reach = look.to_vec3 * 4
    boxes = get_block_hitboxes(eyes, reach)
    Raytrace.raytrace(eyes, reach, boxes).try do |reached|
      location = boxes[reached.box_nr].min.block
      {reached.intercept, location, reached.face}
    end
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
        block_shape = MCData::MC118.block_state_collision_shapes[block_state]
        block_shape.map &.to_f64.offset(x, y, z)
      end || Array(AABBd).new 0 # outside world or outside loaded chunks - XXX make solid so we don't fall through unloaded chunks
    end
  end
end
