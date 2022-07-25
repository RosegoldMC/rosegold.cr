require "../client"

# Updates the player feet/look/velocity/on_ground by sending movement packets.
class Rosegold::Physics
  DRAG    = 0.98 # y velocity multiplicator per tick when not on ground
  GRAVITY = 0.08 # m/t/t; subtracted from y velocity per tick when not on ground

  WALK_SPEED = 4.3 / 20   # m/t
  RUN_SPEED  = 5.612 / 20 # m/t

  JUMP_FORCE = 0.42 # m/t; applied to velocity when starting a jump

  VERY_CLOSE = 0.00001 # consider arrived at target if squared distance is closer than this

  private getter client : Rosegold::Client
  property movement_speed : Float64 = WALK_SPEED
  property movement_target : Vec3d?
  property jump_queued : Bool = false

  def initialize(@client : Rosegold::Client)
    spawn do
      while client.state.is_a? State::Play
        tick
        sleep 0.05 # assume 20 ticks per second for now
      end
    end
  end

  private def player
    client.player
  end

  private def dimension
    client.dimension
  end

  def reset
    # TODO: emit abort event for any ongoing movement
    @movement_target = nil
    @jump_queued = false
  end

  def tick
    prev_feet = player.feet
    prev_look = player.look

    input_velocity = velocity_for_inputs

    movement, player.velocity = Physics.predict_movement_collision(
      player.aabb, input_velocity, dimension)

    player.feet += movement
    # TODO: this only works with gravity on
    player.on_ground = movement.y > input_velocity.y

    # anticheat requires sending these different packets
    if player.feet != prev_feet
      if player.look != prev_look
        client.queue_packet Serverbound::PlayerPositionAndLook.new(
          player.feet, player.look, player.on_ground,
        )
      else
        client.queue_packet Serverbound::PlayerPosition.new player.feet, player.on_ground
      end
    else
      if player.look != prev_look
        client.queue_packet Serverbound::PlayerLook.new player.look, player.on_ground
      else
        client.queue_packet Serverbound::PlayerNoMovement.new player.on_ground
      end
    end
  end

  private def velocity_for_inputs
    curr_movement_target = @movement_target
    if curr_movement_target
      # movement_target only influences x,z; rely on stepping/falling to change y
      move_horiz_vec = (curr_movement_target - player.feet).with_y(0)
      move_horiz_vec_len = move_horiz_vec.len
      if move_horiz_vec_len < VERY_CLOSE
        move_horiz_vec = Vec3d::ORIGIN
        @movement_target = nil
        # TODO: emit "arrival" event
      elsif move_horiz_vec_len > movement_speed
        # take one step of the length of movement_speed
        move_horiz_vec *= movement_speed / move_horiz_vec_len
      end # else: get there in one step
    else
      move_horiz_vec = Vec3d::ORIGIN
    end

    if jump_queued && player.on_ground
      @jump_queued = false
      vel_y = JUMP_FORCE
    else
      vel_y = (player.velocity.y - GRAVITY) * DRAG
    end

    # TODO floating up water/ladders

    Vec3d.new move_horiz_vec.x, vel_y, move_horiz_vec.z
  end

  # Applies collision handling including stepping.
  # Returns adjusted movement vector and adjusted future velocity.
  def self.predict_movement_collision(aabb : AABBd, orig_velocity : Vec3d, dimension : World::Dimension)
    obstacles = get_obstacles aabb, orig_velocity, dimension

    movement = collide_movement aabb, orig_velocity, obstacles
    collided_x = movement.x != orig_velocity.x
    collided_y = movement.y != orig_velocity.y
    collided_z = movement.z != orig_velocity.z
    new_velocity = orig_velocity
    new_velocity = new_velocity.with_x 0 if collided_x
    new_velocity = new_velocity.with_y 0 if collided_y
    new_velocity = new_velocity.with_z 0 if collided_z

    if collided_x || collided_z
      # try stepping
      step_aabb = aabb.offset(0, 0.5, 0)
      # gravity would pull us into the step, preventing stepping
      # TODO: if collision checks are x/z then y, we can keep gravity to end up on top of step
      step_velocity = orig_velocity.with_y 0
      step_movement = collide_movement step_aabb, step_velocity, obstacles

      step_different_x = step_movement.x != movement.x
      step_different_z = step_movement.z != movement.z
      if step_different_x || step_different_z
        movement = step_movement
        new_velocity = step_velocity
        step_collided_x = step_movement.x != orig_velocity.x
        step_collided_z = step_movement.z != orig_velocity.z
        new_velocity = new_velocity.with_x 0 if step_collided_x
        new_velocity = new_velocity.with_z 0 if step_collided_z
      end
    end

    {movement, new_velocity}
  end

  # Updates `vec` according to collision rules.
  # `aabb` is the entity bounding box at the entity's location.
  def self.collide_movement(start_aabb : AABBd, vec : Vec3d, obstacles : Array(AABBd))
    end_aabb = start_aabb.offset vec

    movement = vec # XXX

    if obstacles.any? &.intersects? end_aabb
      movement = movement.with_y start_aabb.min.y.floor - start_aabb.min.y # XXX
    end

    movement
  end

  def self.get_obstacles(start_aabb : AABBd, vec : Vec3d, dimension : World::Dimension)
    moved_aabb = start_aabb.offset vec
    # get all blocks that may potentially collide
    min_hull, max_hull = AABBd.containing_all start_aabb, moved_aabb
    # fences are 1.5 tall so we must check 1.5m below
    min_hull = min_hull.minus(1, 1.5, 1).floored_i32
    # add maximum stepping height (0.5) so we can reuse the obstacles when stepping
    max_hull = max_hull.up(0.5).floored_i32
    blocks_coords = Indexable.cartesian_product({
      (min_hull.x..max_hull.x).to_a,
      (min_hull.y..max_hull.y).to_a,
      (min_hull.z..max_hull.z).to_a,
    })
    obstacles : Array(AABBd) = blocks_coords.flat_map do |block_coords|
      x, y, z = block_coords
      dimension.block_state(x, y, z).try do |block_state|
        block_shape = MCData::MC118.block_state_collision_shapes[block_state]
        block_shape.map(&.to_f64.offset(x, y, z))
      end || Array(AABBd).new 0 # outside world or outside loaded chunks
    end
    # we can freely move in blocks that we already collide with before the movement
    obstacles.reject &.intersects? start_aabb
  end
end
