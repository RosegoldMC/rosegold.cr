require "../client"
require "./action"
require "./raytrace"
require "../events/**"

class Rosegold::Event::PhysicsTick < Rosegold::Event
  getter movement : Vec3d

  def initialize(@movement); end
end

struct Rosegold::VirtualInput
  getter? forward : Bool
  getter? backward : Bool
  getter? left : Bool
  getter? right : Bool
  getter? jump : Bool
  getter? sneak : Bool
  getter? sprint : Bool

  def initialize(@forward : Bool, @backward : Bool, @left : Bool, @right : Bool, @jump : Bool, @sneak : Bool, @sprint : Bool)
  end

  def has_movement_input?
    forward? || backward? || left? || right?
  end
end

# Updates the player feet/look/velocity/on_ground by sending movement packets.
class Rosegold::Physics
  DRAG    = 0.98 # y velocity multiplicator per tick when not on ground
  GRAVITY = 0.08 # m/t/t; subtracted from y velocity each tick when not on ground

  BASE_MOVEMENT_SPEED =        0.1 # Actual player movement attribute
  FRICTION_CONSTANT   = 0.21600002 # The magic number for friction calculation
  SNEAK_MULTIPLIER    =        0.3 # 30% of base speed when sneaking
  SPRINT_MULTIPLIER   =        1.3 # 30% boost for sprinting

  JUMP_FORCE = 0.42 # m/t; applied to velocity when starting a jump

  # Block slipperiness values
  DEFAULT_SLIP  =   0.6 # Default block slipperiness
  SLIME_SLIP    =   0.8 # Slime block slipperiness
  ICE_SLIP      =  0.98 # Ice and Packed Ice slipperiness
  BLUE_ICE_SLIP = 0.989 # Blue Ice slipperiness (most slippery)
  AIR_SLIP      =   1.0 # Air has no friction

  VERY_CLOSE = 0.1

  # Send a keep-alive movement packet every 20 ticks (1 second) even when stationary
  # This prevents server timeouts while avoiding packet spam
  MOVEMENT_PACKET_KEEP_ALIVE_INTERVAL = 20

  private getter client : Rosegold::Client
  property? paused : Bool = true
  property? jump_queued : Bool = false
  property? forward_key : Bool = false
  property? backward_key : Bool = false
  property? left_key : Bool = false
  property? right_key : Bool = false
  private getter movement_action : Action(Vec3d)?
  private getter look_action : Action(Look)?
  private getter action_mutex : Mutex = Mutex.new

  private property jump_trigger_time : Int32 = 0   # For double-tap mechanics
  private property sprint_trigger_time : Int32 = 0 # For double-tap sprint
  private property no_jump_delay : Int32 = 0       # Jump spam prevention

  private property movement_input : Vec3d = Vec3d::ORIGIN
  private property jumping_input : Bool = false

  # Movement stuck tracking
  private property consecutive_stuck_ticks : Int32 = 0
  private property last_position : Vec3d? = nil
  private property current_stuck_timeout_ticks : Int32 = 0

  # Movement packet rate limiting
  property last_sent_feet : Vec3d = Vec3d::ORIGIN
  property last_sent_look : Look = Look::SOUTH
  property last_sent_on_ground : Bool = false # ameba:disable Naming/QueryBoolMethods
  private property ticks_since_last_packet : Int32 = 0

  # Input state tracking for PlayerInput packet
  private property last_sent_input_flags : Serverbound::PlayerInput::Flag = Serverbound::PlayerInput::Flag::None

  def movement_target
    movement_action.try &.target
  end

  def look_target
    look_action.try &.target
  end

  def initialize(@client : Rosegold::Client); end

  def look=(target : Look)
    if paused?
      Log.warn { "Ignoring look of #{target} because physics is paused" }
      return
    end

    action = Action.new(target)
    replace_look_action(action)
    action.join
  end

  def pause
    @paused = true
  end

  def unpause_for_spawn_chunk
    @paused = false
    Log.debug { "Physics unpaused after spawn chunk loaded" }
  end

  def running?
    !paused?
  end

  def handle_reset
    spawn_chunk_x = player.feet.x.to_i >> 4
    spawn_chunk_z = player.feet.z.to_i >> 4
    spawn_chunk_loaded = client.dimension.chunks.has_key?({spawn_chunk_x, spawn_chunk_z})

    if spawn_chunk_loaded
      @paused = false
      Log.debug { "Physics unpaused - spawn chunk (#{spawn_chunk_x}, #{spawn_chunk_z}) is loaded" }
    else
      @paused = true
      Log.debug { "Physics remains paused - waiting for spawn chunk (#{spawn_chunk_x}, #{spawn_chunk_z}) to load" }
    end

    player.velocity = Vec3d::ORIGIN
    player.on_ground = false

    @last_sent_feet = player.feet
    @last_sent_on_ground = player.on_ground?
    @ticks_since_last_packet = 0
    @last_sent_input_flags = Serverbound::PlayerInput::Flag::None
  end

  def handle_disconnect
    @paused = true
    @movement_action.try &.fail Client::NotConnected.new "Disconnected from server"
    stop_moving
    @look_action.try &.fail Rosegold::Client::NotConnected.new "Disconnected from server"
    @look_action = nil
  end

  # Set the movement target location and wait until it is achieved.
  # If there is already a movement target, it is cancelled, and replaced with this new target.
  # Set `target=nil` to stop moving and cancel any current movement.
  # `stuck_timeout_ticks` specifies how many consecutive stuck ticks before throwing MovementStuck.
  def move(target : Vec3d?, stuck_timeout_ticks : Int32 = 10)
    if paused?
      Log.warn { "Ignoring movement to #{target} because physics is paused" }
      return
    end

    if very_close_to? target
      replace_movement_action(nil)
      return
    end

    if target == nil
      replace_movement_action(nil)
      return
    end

    action = Action(Vec3d).new(target)
    replace_movement_action(action)
    # Reset stuck tracking for new movement
    @consecutive_stuck_ticks = 0
    @last_position = nil
    @current_stuck_timeout_ticks = stuck_timeout_ticks
    action.join
  end

  def stop_moving
    @movement_action.try &.cancel
    @movement_action = nil
    @forward_key = false
    @backward_key = false
    @left_key = false
    @right_key = false
  end

  def sneak(sneaking = true)
    return if player.sneaking? == sneaking

    sprint false if sneaking

    player.sneaking = sneaking
  end

  def sprint(sprinting = true)
    return if player.sneaking?
    return if player.sprinting? == sprinting
    player.sprinting = sprinting
  end

  def reset_jump_delay
    @no_jump_delay = 0
  end

  def block_slip : Float64
    feet_pos = player.feet
    block_x = feet_pos.x.floor.to_i
    block_y = (feet_pos.y - 0.5).floor.to_i
    block_z = feet_pos.z.floor.to_i

    block_state = client.dimension.block_state(block_x, block_y, block_z)
    return DEFAULT_SLIP unless block_state

    block_name = MCData::DEFAULT.block_state_names[block_state]
    base_block_name = block_name.split('[').first

    case base_block_name
    when "blue_ice"
      BLUE_ICE_SLIP
    when "ice", "packed_ice", "frosted_ice"
      ICE_SLIP
    when "slime_block"
      SLIME_SLIP
    else
      DEFAULT_SLIP
    end
  end

  private def player
    client.player
  end

  private def replace_movement_action(new_action : Action(Vec3d)?)
    action_mutex.synchronize do
      @movement_action.try &.cancel
      @movement_action = new_action
    end
  end

  private def replace_look_action(new_action : Action(Look)?)
    action_mutex.synchronize do
      @look_action.try &.cancel
      @look_action = new_action
    end
  end

  private def current_player_aabb : AABBf
    # TODO crawling
    return Player::SNEAKING_AABB if player.sneaking?
    Player::DEFAULT_AABB
  end

  private def dimension
    client.dimension
  end

  def tick
    return if paused? || !client.connected?

    input = convert_movement_goals_to_input
    process_virtual_input(input)

    movement, next_velocity, new_feet, on_ground = execute_movement_physics

    player.feet = new_feet
    player.on_ground = on_ground

    track_stuck_movement(new_feet)

    send_input_if_changed(input)
    sync_with_server

    player.velocity = next_velocity

    complete_actions(new_feet)

    client.emit_event Event::PhysicsTick.new movement
  end

  private def convert_movement_goals_to_input : Rosegold::VirtualInput
    curr_movement = @movement_action

    if curr_movement
      move_direction = (curr_movement.target - player.feet).with_y(0)

      # override keys during movement_action
      @forward_key = false
      @backward_key = false
      @left_key = false
      @right_key = false
      if move_direction.length >= VERY_CLOSE
        @forward_key = true
        target_yaw = Math.atan2(-move_direction.x, move_direction.z) * (180.0 / Math::PI)
        target_look = Look.new(target_yaw.to_f32, player.look.pitch)
        player.look = target_look
      end
    end

    jump = jump_queued? && player.on_ground?
    sneak = player.sneaking?
    sprint = player.sprinting? && !sneak

    Rosegold::VirtualInput.new(
      forward: @forward_key,
      backward: @backward_key,
      left: @left_key,
      right: @right_key,
      jump: jump,
      sneak: sneak,
      sprint: sprint
    )
  end

  def very_close_to?(target : Vec3d)
    distance = (target - player.feet).with_y(0).length
    is_close = distance < VERY_CLOSE
    is_close
  end

  private def movement_changed?
    player.feet != last_sent_feet ||
      player.look != last_sent_look ||
      player.on_ground? != last_sent_on_ground
  end

  class MovementStuck < Exception; end

  private def process_virtual_input(input : Rosegold::VirtualInput)
    process_input_timing

    @movement_input = calculate_movement_vector(input)
    @jumping_input = input.jump? && can_jump?

    handle_sprint_mechanics(input)

    apply_input_state_transitions(input)
  end

  private def process_input_timing
    @jump_trigger_time = [@jump_trigger_time - 1, 0].max
    @sprint_trigger_time = [@sprint_trigger_time - 1, 0].max
    @no_jump_delay = [@no_jump_delay - 1, 0].max
  end

  private def calculate_movement_vector(input : Rosegold::VirtualInput) : Vec3d
    strafe = 0.0
    forward = 0.0

    strafe += 1.0 if input.left?
    strafe -= 1.0 if input.right?
    forward += 1.0 if input.forward?
    forward -= 1.0 if input.backward?

    if strafe != 0.0 && forward != 0.0
      diagonal_factor = Math.sin(Math::PI / 4.0)
      strafe *= diagonal_factor
      forward *= diagonal_factor
    end

    Vec3d.new(strafe, 0.0, forward)
  end

  private def can_jump? : Bool
    player.on_ground? && @no_jump_delay <= 0
  end

  private def handle_sprint_mechanics(input : Rosegold::VirtualInput)
    should_sprint = input.sprint? && input.has_movement_input? && !input.sneak?

    if should_sprint != player.sprinting?
      sprint(should_sprint)
    end
  end

  private def apply_input_state_transitions(input : Rosegold::VirtualInput)
    if @jumping_input && player.on_ground?
      @jump_queued = false
      @no_jump_delay = 10
    end

    if input.sneak? != player.sneaking?
      sneak(input.sneak?)
    end
  end

  private def execute_movement_physics : {Vec3d, Vec3d, Vec3d, Bool}
    input_velocity = velocity_from_movement_input

    movement, post_collision_velocity = Physics.predict_movement_collision(
      player.feet, input_velocity, current_player_aabb, dimension)

    if player.on_ground?
      slip = block_slip
      drag_factor = slip * 0.91
      final_velocity = Vec3d.new(
        post_collision_velocity.x * drag_factor,
        post_collision_velocity.y * 0.98, post_collision_velocity.z * drag_factor
      )
    else
      final_velocity = Vec3d.new(
        post_collision_velocity.x * 0.91,
        post_collision_velocity.y * 0.98, post_collision_velocity.z * 0.91
      )
    end

    new_feet = player.feet + movement

    on_ground = movement.y > input_velocity.y

    {movement, final_velocity, new_feet, on_ground}
  end

  # Refactored velocity calculation using the processed movement input
  private def velocity_from_movement_input : Vec3d
    existing_velocity = player.velocity

    # 1. Calculate friction-influenced speed (like getFrictionInfluencedSpeed)
    if player.on_ground?
      slip = block_slip
      friction_cubed = slip * slip * slip
      # Correct Minecraft formula: base_speed * (friction_constant / friction³)
      movement_multiplier = BASE_MOVEMENT_SPEED * (FRICTION_CONSTANT / friction_cubed)

      # Apply movement state modifiers
      if player.sneaking?
        movement_multiplier *= SNEAK_MULTIPLIER
      elsif player.sprinting?
        movement_multiplier *= SPRINT_MULTIPLIER
      end
    else
      movement_multiplier = 0.02 # Air movement
    end

    # 2. Apply moveRelative transformation (like Minecraft's getInputVector)
    input_length_sq = @movement_input.length * @movement_input.length
    if input_length_sq < 1.0e-7
      input_velocity = Vec3d::ORIGIN
    else
      # Normalize if length > 1
      normalized_input = input_length_sq > 1.0 ? @movement_input.normed : @movement_input
      scaled_input = normalized_input * movement_multiplier

      # Rotate by player yaw (critical step that was missing!)
      yaw_rad = player.look.yaw_rad
      sin_yaw = Math.sin(yaw_rad)
      cos_yaw = Math.cos(yaw_rad)

      input_velocity = Vec3d.new(
        scaled_input.x * cos_yaw - scaled_input.z * sin_yaw,
        scaled_input.y,
        scaled_input.z * cos_yaw + scaled_input.x * sin_yaw
      )
    end

    combined_velocity = existing_velocity + input_velocity

    vel_y = if @jumping_input && player.on_ground?
              if player.sprinting? && combined_velocity.length > 0
                direction = Vec3d.new(combined_velocity.x, 0, combined_velocity.z).normed
                combined_velocity = Vec3d.new(
                  combined_velocity.x + direction.x * 0.2,
                  combined_velocity.y,
                  combined_velocity.z + direction.z * 0.2
                )
              end

              JUMP_FORCE
            else
              combined_velocity.y - 0.08
            end

    horiz_length = Vec3d.new(combined_velocity.x, 0, combined_velocity.z).length
    if horiz_length < 0.003
      combined_velocity = Vec3d.new(0, combined_velocity.y, 0)
    end

    Vec3d.new(combined_velocity.x, vel_y, combined_velocity.z)
  end

  private def sync_with_server
    if look_action = @look_action
      player.look = look_action.target
    end

    should_send_packet = movement_changed? || ticks_since_last_packet >= MOVEMENT_PACKET_KEEP_ALIVE_INTERVAL

    if should_send_packet
      send_movement_packet
      @ticks_since_last_packet = 0
    else
      @ticks_since_last_packet += 1
    end
  end

  private def complete_actions(new_feet : Vec3d)
    action_mutex.synchronize do
      @movement_action.try do |movement_action|
        if very_close_to?(movement_action.target)
          target_with_y = Vec3d.new(movement_action.target.x, new_feet.y, movement_action.target.z)
          player.feet = target_with_y
          player.velocity = Vec3d.new(0.0, player.velocity.y, 0.0)
          movement_action.succeed
          stop_moving
        end
      end

      @look_action.try(&.succeed)
      @look_action = nil
    end
  end

  private def track_stuck_movement(feet : Vec3d)
    if action = @movement_action
      if last_pos = @last_position
        if (feet - last_pos).length < 0.001
          @consecutive_stuck_ticks += 1

          if @current_stuck_timeout_ticks > 0 && @consecutive_stuck_ticks >= @current_stuck_timeout_ticks
            action.fail MovementStuck.new "Movement stuck for #{@current_stuck_timeout_ticks} consecutive ticks at #{feet}"
            stop_moving
          end
        else
          @consecutive_stuck_ticks = 0
        end
      end

      @last_position = feet
    end
  end

  private def send_input_if_changed(input : Rosegold::VirtualInput)
    # Convert VirtualInput to PlayerInput flags, matching vanilla behavior
    flags = Serverbound::PlayerInput::Flag::None
    flags |= Serverbound::PlayerInput::Flag::Forward if input.forward?
    flags |= Serverbound::PlayerInput::Flag::Backward if input.backward?
    flags |= Serverbound::PlayerInput::Flag::Left if input.left?
    flags |= Serverbound::PlayerInput::Flag::Right if input.right?
    flags |= Serverbound::PlayerInput::Flag::Jump if input.jump?
    flags |= Serverbound::PlayerInput::Flag::Sneak if input.sneak?
    flags |= Serverbound::PlayerInput::Flag::Sprint if input.sprint?

    # Only send if input state changed, like vanilla
    if flags != @last_sent_input_flags
      client.send_packet! Serverbound::PlayerInput.new(flags)
      @last_sent_input_flags = flags
    end
  end

  private def send_movement_packet
    feet = player.feet
    look = player.look
    on_ground = player.on_ground?

    # anticheat requires sending these different packets
    if feet != last_sent_feet
      if look != last_sent_look
        client.send_packet! Serverbound::PlayerPositionAndLook.new(feet, look, on_ground)
      else
        client.send_packet! Serverbound::PlayerPosition.new feet, on_ground
      end
    else
      if look != last_sent_look
        client.send_packet! Serverbound::PlayerLook.new look, on_ground
      else
        client.send_packet! Serverbound::PlayerNoMovement.new on_ground
      end
    end

    @last_sent_feet = feet
    @last_sent_look = look
    @last_sent_on_ground = on_ground

    client.emit_event Event::PlayerPositionUpdate.new(feet, look)
  end

  # Applies collision handling including stepping.
  # Returns adjusted movement vector and adjusted post-movement velocity.
  def self.predict_movement_collision(start : Vec3d, velocity : Vec3d, entity_aabb : AABBf, dimension : Dimension)
    obstacles = get_grown_obstacles start, velocity, entity_aabb, dimension
    predict_movement_collision start, velocity, obstacles
  end

  # :ditto:
  def self.predict_movement_collision(start : Vec3d, velocity : Vec3d, obstacles : Array(AABBd))
    # we can freely move in blocks that we already collide with before the movement
    obstacles = obstacles.reject &.contains? start

    movement = slide start, velocity, obstacles
    collided_x = movement.x != velocity.x
    collided_y = movement.y != velocity.y
    collided_z = movement.z != velocity.z

    if collided_x || collided_z
      step_up_movement = slide start, Vec3d.new(0, 0.5, 0), obstacles
      step_up = start + step_up_movement
      # gravity would pull us into the step, preventing stepping
      over_velocity = velocity.with_y 0
      step_over_movement = slide step_up, over_velocity, obstacles

      step_different_x = step_over_movement.x != movement.x
      step_different_z = step_over_movement.z != movement.z
      if step_different_x || step_different_z
        # we may have stepped too far up, land on top surface of step block
        step_over = step_up + step_over_movement
        down_velocity = Vec3d.new(0, velocity.y - step_up_movement.y, 0)
        down_end = step_over + slide step_over, down_velocity, obstacles
        movement = down_end - start
        collided_x = movement.x != velocity.x
        collided_y = true
        collided_z = movement.z != velocity.z
      end
    end

    new_velocity = velocity
    new_velocity = new_velocity.with_x 0 if collided_x
    new_velocity = new_velocity.with_y 0 if collided_y
    new_velocity = new_velocity.with_z 0 if collided_z

    {movement, new_velocity}
  end

  # Slide along block faces in three dimensions.
  private def self.slide(start, velocity, obstacles)
    (1..3).each do
      collision = Raytrace.raytrace start, velocity, obstacles
      return velocity unless collision
      # slide parallel to this face
      coord = (collision.intercept - start).axis collision.face
      velocity = velocity.with_axis collision.face, coord
    end
    velocity
  end

  # Returns all block collision boxes that may intersect `entity_aabb` during the movement from `start` by `vec`,
  # including boxes 0.5m higher for stepping.
  # `entity_aabb` is at 0,0,0; the returned AABBs are grown by `entity_aabb` so collision checks are just raytracing.
  def self.get_grown_obstacles(
    start : Vec3d, movement : Vec3d, entity_aabb : AABBf, dimension : Dimension,
  ) : Array(AABBd)
    entity_aabb = entity_aabb.to_f64
    grow_aabb = entity_aabb * -1
    # get all blocks that may potentially collide
    bounds = AABBd.containing_all(
      entity_aabb.offset(start),
      entity_aabb.offset(start + movement))
    # fences are 1.5m tall
    min_block = bounds.min.down(0.5).block
    # add maximum stepping height (0.5) so we can reuse the obstacles when stepping
    max_block = bounds.max.up(0.5).block
    blocks_coords = Indexable.cartesian_product({
      (min_block.x..max_block.x).to_a,
      (min_block.y..max_block.y).to_a,
      (min_block.z..max_block.z).to_a,
    })
    blocks_coords.flat_map do |block_coords|
      x, y, z = block_coords
      dimension.block_state(x, y, z).try do |block_state|
        block_shape = MCData::DEFAULT.block_state_collision_shapes[block_state]
        block_shape.map &.to_f64.offset(x, y, z).grow(grow_aabb)
      end || Array(AABBd).new 0 # outside world or outside loaded chunks - XXX make solid so we don't fall through unloaded chunks
    end
  end
end
