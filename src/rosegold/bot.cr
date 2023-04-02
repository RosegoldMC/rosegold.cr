require "../rosegold"

class Rosegold::Bot
  private getter client : Client

  def initialize(@client); end

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

  # Direction the player is looking.
  def look
    client.player.look
  end

  # Waits for the new look to be sent to the server.
  def look=(look : Look)
    client.physics.look look
  end

  # Computes the new look from the current look.
  # Waits for the new look to be sent to the server.
  def look(&block : Look -> Look)
    client.physics.look block.call look
  end

  # Waits for the new look to be sent to the server.
  def look(look : Look)
    client.physics.look look
  end

  # Waits for the new look to be sent to the server.
  def look(vec : Vec3d)
    client.physics.look vec
  end

  # Waits for the new look to be sent to the server.
  def look_at(location : Vec3d)
    client.physics.look Look.from_vec location - eyes
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

  # Does nothing if there is no current movement target.
  def stop_moving
    client.physics.move nil
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

  def interact_block(location : Vec3d, face : BlockFace, look = true)
    place_block_against(location, face, look, 0)
  end

  # Raises an error if the hand slot is not updated within `timeout_ticks`.
  def place_block_against(location : Vec3d, face : BlockFace, look = true, timeout_ticks = 0)
    cursor = (location - location.floored).to_f32
    hand = Hand::MainHand # TODO
    inside_block = false  # TODO
    client.connection.send_packet Serverbound::PlayerBlockPlacement.new \
      location.floored_i32, face, cursor, hand, inside_block
    client.connection.send_packet Serverbound::SwingArm.new hand
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

  # All player slots are remembered but may not be updated while another window is open.

  def equipment
    # TODO client.inventory_window.equipment
  end

  def inventory
    # TODO client.inventory_window.inventory
  end

  def hotbar
    # TODO client.inventory_window.hotbar
  end

  def main_hand
    # TODO client.inventory_window.hotbar[hotbar_selection]
  end

  def off_hand
    # TODO client.inventory_window.off_hand
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
  @digging_location : Vec3d?

  # waits for completion
  def dig(location : Vec3d, face : BlockFace, ticks : UInt32, look = true)
    raise "Not implemented" # TODO
  end

  def start_digging(location : Vec3d, face : BlockFace, look = true)
    raise "Not implemented" # TODO
  end

  def finish_digging
    raise "Not implemented" # TODO
  end

  def cancel_digging
    raise "Not implemented" # TODO
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
end
