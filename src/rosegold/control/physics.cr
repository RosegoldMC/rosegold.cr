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

  WATER_DRAG          =   0.8 # velocity multiplier per tick in water (all axes)
  WATER_GRAVITY       = 0.005 # reduced gravity in water (0.08 / 16)
  WATER_SWIM_UP_SPEED =  0.04 # upward velocity per tick when pressing jump in water

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

  MAX_UP_STEP = 0.6

  VERY_CLOSE = 0.1

  # Epsilon constants for floating point precision
  EPSILON_COLLISION  = 1.0e-7
  EPSILON_MOVEMENT   = 1.0e-6
  EPSILON_STUCK      =  0.001
  EPSILON_HORIZONTAL =  0.003

  # Send a keep-alive movement packet every 20 ticks (1 second) even when stationary
  # This prevents server timeouts while avoiding packet spam
  MOVEMENT_PACKET_KEEP_ALIVE_INTERVAL = 20

  private getter client : Rosegold::Client
  property? paused : Bool = true
  property? jump_queued : Bool = false
  getter keys : MovementKeys = MovementKeys.new
  private getter movement_action : Action(Vec3d)?
  private getter look_action : Action(Look)?
  private getter action_mutex : Mutex = Mutex.new

  private property jump_trigger_time : Int32 = 0   # For double-tap mechanics
  private property sprint_trigger_time : Int32 = 0 # For double-tap sprint
  private property sprint_requested : Bool = false
  private property no_jump_delay : Int32 = 0 # Jump spam prevention

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

  # Queued velocity from SetEntityMotion, applied at tick start to avoid race conditions.
  # Vanilla processes packets on the main thread between ticks; this emulates that.
  @pending_velocity : Vec3d? = nil
  @pending_velocity_mutex : Mutex = Mutex.new

  def movement_target
    movement_action.try &.target
  end

  def look_target
    look_action.try &.target
  end

  def initialize(@client : Rosegold::Client); end

  # Queue a velocity replacement from a packet callback (e.g., SetEntityMotion).
  # Applied at the start of the next tick to avoid mid-tick overwrites.
  def pending_velocity=(velocity : Vec3d)
    @pending_velocity_mutex.synchronize { @pending_velocity = velocity }
  end

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

    player.on_ground = false
    player.fall_distance = 0.0

    # Clear any queued velocity from SetEntityMotion to prevent stale
    # knockback from being applied after respawn/dimension change
    @pending_velocity_mutex.synchronize { @pending_velocity = nil }

    @last_sent_feet = player.feet
    @last_sent_on_ground = player.on_ground?
    @ticks_since_last_packet = 0
    @last_sent_input_flags = Serverbound::PlayerInput::Flag::None
  end

  def handle_disconnect
    @paused = true
    stop_moving
    @look_action.try &.cancel
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
    replace_movement_action(nil)
    keys.release_all
  end

  def sneak(sneaking = true)
    return if player.sneaking? == sneaking

    sprint false if sneaking

    player.sneaking = sneaking
    # Sneaking is handled via PlayerInput Sneak flag (bit 0x20)
  end

  def sprint(sprinting = true)
    @sprint_requested = sprinting
    apply_sprint_state(sprinting)
  end

  private def apply_sprint_state(sprinting : Bool)
    return if player.sneaking?
    return if player.sprinting? == sprinting
    player.sprinting = sprinting

    # Server requires EntityAction (PlayerCommand) for sprint state changes
    if sprinting
      client.send_packet! Serverbound::EntityAction.new(player.entity_id, :start_sprinting)
    else
      client.send_packet! Serverbound::EntityAction.new(player.entity_id, :stop_sprinting)
    end
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

    block_name = MCData.default.block_state_names[block_state]
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

  private def player_in_water? : Bool
    feet_pos = player.feet
    block_names = MCData.default.block_state_names

    # Check blocks at feet and body level
    return true if water_block_at?(block_names, feet_pos.x.floor.to_i, feet_pos.y.floor.to_i, feet_pos.z.floor.to_i)
    return true if water_block_at?(block_names, feet_pos.x.floor.to_i, (feet_pos.y + 0.4).floor.to_i, feet_pos.z.floor.to_i)
    false
  end

  private def water_block_at?(block_names, block_x : Int32, block_y : Int32, block_z : Int32) : Bool
    block_state = client.dimension.block_state(block_x, block_y, block_z)
    return false unless block_state
    name = block_names[block_state]
    base_name = name.split('[').first
    return true if base_name == "water" || base_name == "bubble_column"
    name.includes?("waterlogged=true")
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

    # Apply queued velocity from packet callbacks before physics runs
    @pending_velocity_mutex.synchronize do
      if pv = @pending_velocity
        player.velocity = pv
        @pending_velocity = nil
      end
    end

    input = convert_movement_goals_to_input
    process_virtual_input(input)

    movement, next_velocity, new_feet, on_ground = execute_movement_physics

    player.feet = new_feet
    player.on_ground = on_ground

    if on_ground
      player.fall_distance = 0.0
    elsif movement.y < 0
      player.fall_distance -= movement.y
    end

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

      keys.release_all
      if move_direction.length >= VERY_CLOSE
        keys.press MovementKeys::Key::Forward
        target_yaw = Math.atan2(-move_direction.x, move_direction.z) * (180.0 / Math::PI)
        target_look = Look.new(target_yaw.to_f32, player.look.pitch)
        player.look = target_look
      end
    end

    jump = jump_queued? && (player.on_ground? || player.in_water?)
    sneak = player.sneaking?
    sprint = @sprint_requested && !sneak

    Rosegold::VirtualInput.new(
      forward: keys.forward?,
      backward: keys.backward?,
      left: keys.left?,
      right: keys.right?,
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
    @jumping_input = if player.in_water?
                       jump_queued?
                     else
                       input.jump? && can_jump?
                     end

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
      apply_sprint_state(should_sprint)
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

  private def velocity_multiplier : Float64
    feet_pos = player.feet
    block_x = feet_pos.x.floor.to_i
    block_y = (feet_pos.y - 0.5).floor.to_i
    block_z = feet_pos.z.floor.to_i

    block_state = client.dimension.block_state(block_x, block_y, block_z)
    return 1.0 unless block_state

    block_name = MCData.default.block_state_names[block_state]
    base_block_name = block_name.split('[').first

    case base_block_name
    when "soul_sand", "honey_block"
      0.4
    else
      1.0
    end
  end

  private def in_cobweb? : Bool
    feet_pos = player.feet
    body_pos = feet_pos.up(0.9)

    [feet_pos, body_pos].any? do |pos|
      bx = pos.x.floor.to_i
      by = pos.y.floor.to_i
      bz = pos.z.floor.to_i
      block_state = client.dimension.block_state(bx, by, bz)
      next false unless block_state
      block_name = MCData.default.block_state_names[block_state]
      block_name.split('[').first == "cobweb"
    end
  end

  private def execute_movement_physics : {Vec3d, Vec3d, Vec3d, Bool}
    input_velocity = velocity_from_movement_input

    # Apply velocity multiplier (soul sand, honey block)
    vel_mult = velocity_multiplier
    if vel_mult < 1.0
      input_velocity = Vec3d.new(input_velocity.x * vel_mult, input_velocity.y, input_velocity.z * vel_mult)
    end

    input_velocity = maybe_back_off_from_edge(input_velocity)

    movement, post_collision_velocity = Physics.predict_movement_collision(
      player.feet, input_velocity, current_player_aabb, dimension)

    in_water = player_in_water?
    player.in_water = in_water

    if in_water
      # Water physics: drag first (0.8 all axes), then reduced gravity (0.005)
      # Vanilla: LivingEntity.travelInWater — multiply by drag, subtract gravity/16
      final_velocity = Vec3d.new(
        post_collision_velocity.x * WATER_DRAG,
        post_collision_velocity.y * 0.8 - WATER_GRAVITY,
        post_collision_velocity.z * WATER_DRAG
      )
    else
      # Apply gravity/levitation AFTER collision, matching Minecraft's LivingEntity.travel() order:
      # 1. moveRelative (input) → 2. move (collision) → 3. gravity/levitation → 4. drag
      levitation = player.levitation_level
      if levitation > 0
        target_vel = 0.05 * levitation
        new_y = post_collision_velocity.y + (target_vel - post_collision_velocity.y) * 0.2
        post_collision_velocity = Vec3d.new(post_collision_velocity.x, new_y, post_collision_velocity.z)
      else
        gravity = if player.has_slow_falling? && post_collision_velocity.y <= 0
                    0.01
                  else
                    GRAVITY
                  end
        post_collision_velocity = post_collision_velocity - Vec3d.new(0, gravity, 0)
      end

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
    end

    # Apply cobweb slowdown
    if in_cobweb?
      final_velocity = Vec3d.new(
        final_velocity.x * 0.25,
        final_velocity.y * 0.05,
        final_velocity.z * 0.25
      )
    end

    new_feet = player.feet + movement

    # Ground detection: check if we collided vertically while moving downward
    vertical_collision = (movement.y - input_velocity.y).abs > EPSILON_MOVEMENT
    on_ground = vertical_collision && input_velocity.y < 0

    {movement, final_velocity, new_feet, on_ground}
  end

  # Refactored velocity calculation using the processed movement input
  private def velocity_from_movement_input : Vec3d
    existing_velocity = player.velocity

    # 1. Calculate friction-influenced speed (like getFrictionInfluencedSpeed)
    if player.in_water?
      movement_multiplier = 0.02 # Water movement (same base as air, drag handles the rest)
    elsif player.on_ground?
      slip = block_slip
      friction_cubed = slip * slip * slip
      # Correct Minecraft formula: base_speed * (friction_constant / friction³)
      # Apply Speed and Slowness potion effects to base movement speed
      effective_speed = Math.max(0.0, BASE_MOVEMENT_SPEED * (1.0 + 0.2 * player.speed_level) * (1.0 - 0.15 * player.slowness_level))
      movement_multiplier = effective_speed * (FRICTION_CONSTANT / friction_cubed)

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

    vel_y = if player.in_water? && @jumping_input
              # Swimming upward in water — no jump force, just steady upward push
              combined_velocity.y + WATER_SWIM_UP_SPEED
            elsif @jumping_input && player.on_ground?
              if player.sprinting? && combined_velocity.length > 0
                direction = Vec3d.new(combined_velocity.x, 0, combined_velocity.z).normed
                combined_velocity = Vec3d.new(
                  combined_velocity.x + direction.x * 0.2,
                  combined_velocity.y,
                  combined_velocity.z + direction.z * 0.2
                )
              end

              JUMP_FORCE + 0.1 * player.jump_boost_level
            else
              combined_velocity.y
            end

    horiz_length = Vec3d.new(combined_velocity.x, 0, combined_velocity.z).length
    if horiz_length < 0.003
      combined_velocity = Vec3d.new(0, combined_velocity.y, 0)
    end

    Vec3d.new(combined_velocity.x, vel_y, combined_velocity.z)
  end

  private def maybe_back_off_from_edge(velocity : Vec3d) : Vec3d
    return velocity unless player.sneaking?
    return velocity if player.flying?
    return velocity if velocity.y > 0.0
    return velocity unless above_ground?

    entity_aabb = current_player_aabb
    Physics.maybe_back_off_from_edge(player.feet, velocity, entity_aabb) do |test_aabb|
      no_collision?(test_aabb)
    end
  end

  private def above_ground? : Bool
    player.on_ground? || (player.fall_distance < MAX_UP_STEP &&
      !can_fall_at_least?(0.0, 0.0, MAX_UP_STEP - player.fall_distance))
  end

  private def can_fall_at_least?(dx : Float64, dz : Float64, max_fall_dist : Float64) : Bool
    test_aabb = Physics.make_fall_test_aabb(
      player.feet, current_player_aabb.to_f64, dx, dz, max_fall_dist, EPSILON_COLLISION)
    no_collision?(test_aabb)
  end

  private def no_collision?(box : AABBd) : Bool
    min_block = box.min.block
    max_block = box.max.block
    block_coords = Indexable.cartesian_product({
      (min_block.x..max_block.x).to_a,
      (min_block.y..max_block.y).to_a,
      (min_block.z..max_block.z).to_a,
    })
    block_coords.each do |coords|
      bx, by, bz = coords
      block_state = dimension.block_state(bx, by, bz)
      if block_state
        shapes = MCData.default.block_state_collision_shapes[block_state]
        shapes.each do |shape|
          block_aabb = shape.to_f64.offset(bx.to_f64, by.to_f64, bz.to_f64)
          return false if box.intersects?(block_aabb)
        end
      else
        return false
      end
    end
    true
  end

  def self.maybe_back_off_from_edge(
    feet : Vec3d, velocity : Vec3d, entity_aabb : AABBf,
    &would_fall : AABBd -> Bool
  ) : Vec3d
    x = velocity.x
    z = velocity.z
    step = 0.05
    entity_aabb_d = entity_aabb.to_f64
    step_x = x.sign * step
    step_z = z.sign * step

    while x != 0.0
      test_aabb = make_fall_test_aabb(feet, entity_aabb_d, x, 0.0, MAX_UP_STEP, EPSILON_COLLISION)
      break unless would_fall.call(test_aabb)
      if x.abs <= step
        x = 0.0
        break
      end
      x -= step_x
    end

    while z != 0.0
      test_aabb = make_fall_test_aabb(feet, entity_aabb_d, 0.0, z, MAX_UP_STEP, EPSILON_COLLISION)
      break unless would_fall.call(test_aabb)
      if z.abs <= step
        z = 0.0
        break
      end
      z -= step_z
    end

    while x != 0.0 && z != 0.0
      test_aabb = make_fall_test_aabb(feet, entity_aabb_d, x, z, MAX_UP_STEP, EPSILON_COLLISION)
      break unless would_fall.call(test_aabb)
      if x.abs <= step
        x = 0.0
      else
        x -= step_x
      end
      if z.abs <= step
        z = 0.0
      else
        z -= step_z
      end
    end

    Vec3d.new(x, velocity.y, z)
  end

  protected def self.make_fall_test_aabb(
    feet : Vec3d, entity_aabb : AABBd,
    dx : Float64, dz : Float64, max_fall_dist : Float64, epsilon : Float64,
  ) : AABBd
    AABBd.new(
      entity_aabb.min.x + epsilon + dx + feet.x,
      feet.y - max_fall_dist - epsilon,
      entity_aabb.min.z + epsilon + dz + feet.z,
      entity_aabb.max.x - epsilon + dx + feet.x,
      feet.y,
      entity_aabb.max.z - epsilon + dz + feet.z,
    )
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
          @movement_action = nil
          keys.release_all
        end
      end

      @look_action.try do |look_act|
        if player.look == look_act.target
          look_act.succeed
          @look_action = nil
        end
      end
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
    # Use epsilon to detect meaningful collisions vs floating point noise
    collided_x = (movement.x - velocity.x).abs > EPSILON_COLLISION
    collided_y = (movement.y - velocity.y).abs > EPSILON_COLLISION
    collided_z = (movement.z - velocity.z).abs > EPSILON_COLLISION

    if collided_x || collided_z
      step_up_movement = slide start, Vec3d.new(0, MAX_UP_STEP, 0), obstacles
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

  # Returns all block collision boxes that may intersect `entity_aabb` during the movement from `start` by `vec`.
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
    # add maximum stepping height so we can reuse the obstacles when stepping
    max_block = bounds.max.up(MAX_UP_STEP).block
    blocks_coords = Indexable.cartesian_product({
      (min_block.x..max_block.x).to_a,
      (min_block.y..max_block.y).to_a,
      (min_block.z..max_block.z).to_a,
    })
    blocks_coords.flat_map do |block_coords|
      x, y, z = block_coords
      dimension.block_state(x, y, z).try do |block_state|
        block_shape = MCData.default.block_state_collision_shapes[block_state]
        block_shape.map &.to_f64.offset(x, y, z).grow(grow_aabb)
      end || begin
        # Unloaded chunks should be solid to prevent falling through
        [AABBd.new(x.to_f64, y.to_f64, z.to_f64,
          x.to_f64 + 1.0, y.to_f64 + 1.0, z.to_f64 + 1.0).grow(grow_aabb)]
      end
    end
  end
end
