require "../client"
require "../world/look"
require "../world/vec3"
require "./physics"

class Rosegold::Interactions
  private class ReachedBlock
    getter intercept : Vec3d, block : Vec3i, face : BlockFace

    def initialize(@intercept, @block, @face); end
  end

  # not exposed, for rules compliance
  @using_hand = false
  @digging_block : ReachedBlock?
  @dig_hand_swing_countdown = 0_i8

  getter client : Client
  property? digging : Bool = false

  def initialize(@client)
    client.on Event::PhysicsTick do
      on_physics_tick
    end
  end

  # Activates the "use" button.
  def start_using_hand(hand : Hand = :main_hand)
    reached = reach_block_or_entity
    if reached
      place_block hand, reached
    else
      @using_hand = true
      send_packet Serverbound::UseItem.new hand
      send_packet Serverbound::SwingArm.new
    end
  end

  # Deactivates the "use" button.
  def stop_using_hand
    return unless @using_hand
    @using_hand = false
    send_packet Serverbound::PlayerDigging.new :finish_using_hand
  end

  # Activates the "attack" button.
  def start_digging
    return if digging?
    self.digging = true

    spawn do
      while digging?
        cancel = false
        reached = reach_block_or_entity
        sleep 1.tick
        next sleep 1.tick unless reached

        start_digging reached

        client.dimension.block_state(reached.block).try do |block_state|
          block = Block.from_block_state_id block_state
          next sleep 1.tick if block.id_str == "air"

          block.break_time(inventory.main_hand, client.player).to_i.times do
            sleep 1.tick
            reached = reach_block_or_entity
            if reached.try &.block != @digging_block.try &.block
              cancel_digging
              cancel = true
              break
            end
          end
        end

        finish_digging if digging? && !cancel
      end
    end
  end

  # Deactivates the "attack" button.
  def stop_digging
    return unless digging?
    self.digging = false
    cancel_digging
  end

  private def on_physics_tick
    # TODO if buttons are being held, keep placing more blocks or throwing/eating more items
    if @digging_block
      @dig_hand_swing_countdown -= 1
      if @dig_hand_swing_countdown <= 0
        @dig_hand_swing_countdown = 6
        send_packet Serverbound::SwingArm.new
      end
    end
  end

  private def send_packet(packet)
    client.queue_packet packet
  end

  private def place_block(hand : Hand, reached : ReachedBlock)
    cursor = (reached.intercept - reached.block.to_f64).to_f32
    inside_block = false # TODO
    send_packet Serverbound::PlayerBlockPlacement.new \
      reached.block, reached.face, cursor, hand, inside_block
    send_packet Serverbound::SwingArm.new hand
  end

  private def start_digging(reached : ReachedBlock)
    @digging_block = reached
    @dig_hand_swing_countdown = 6

    send_packet Serverbound::PlayerDigging.new \
      :start, reached.block, reached.face
    send_packet Serverbound::SwingArm.new
  end

  def finish_digging
    reached = @digging_block
    return unless reached
    @digging_block = nil
    send_packet Serverbound::PlayerDigging.new \
      :finish, reached.block, reached.face
  end

  # TODO decide finish/cancel based on block dig time
  def cancel_digging
    reached = @digging_block
    return unless reached
    @digging_block = nil
    send_packet Serverbound::PlayerDigging.new \
      :cancel, reached.block, reached.face
  end

  private def reach_block_or_entity : ReachedBlock?
    reach_len = 4.5
    reach_len = 5.0 if client.player.gamemode == 1
    reach_vec = client.player.look.to_vec3 * reach_len
    eyes = client.player.eyes
    boxes = get_block_hitboxes(eyes, reach_vec)
    Raytrace.raytrace(eyes, reach_vec, boxes).try do |reached|
      block = boxes[reached.box_nr].min.block
      ReachedBlock.new reached.intercept, block, reached.face
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

  private def inventory : Inventory
    @inventory ||= Inventory.new client
  end
end
