require "../rosegold"

enum BlockFace
  Bottom; Top; West; East; North; South
end

enum Hand
  MainHand; OffHand
end

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
  # To change the location, use #walk_to.
  def feet
    client.player.feet
  end

  # Location of the player's eyes.
  # To change the location, use #walk_to.
  def eyes
    client.player.eyes
  end

  # Walks straight towards `location`.
  # Waits for arrival.
  def walk_to(location : Vec3d)
    client.physics.move location
  end

  # Walks straight towards `location`.
  # Waits for arrival.
  def walk_to(x : Float64, z : Float64)
    client.physics.move Vec3d.new x, feet.y, z
  end

  # Computes the destination location from the current feet location.
  # Walks straight towards the destination.
  # Waits for arrival.
  def walk_to(&block : Vec3d -> Vec3d)
    client.physics.move block.call feet
  end

  # Does nothing if there is no current walk target.
  def stop_walking
    client.physics.move nil
  end

  # Jumps the next time the player is on the ground.
  def start_jump
    client.physics.jump_queued = true
  end

  def leave_bed
    raise "Not implemented" # TODO send packet
  end

  def activate_block(location : Vec3d, face : BlockFace, look = true)
    raise "Not implemented" # TODO send packet
  end

  # Raises an error if the hand slot is not updated within `timeout_ticks`.
  def place_block_against(location : Vec3d, face : BlockFace, look = true, timeout_ticks = 0)
    raise "Not implemented" # TODO send packet
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

  # All player slots are remembered even when a window is open.

  def equipment
    client.player.equipment
  end

  def inventory
    client.player.inventory
  end

  def hotbar
    client.player.hotbar
  end

  def main_hand
    client.player.hotbar[hotbar_selection]
  end

  def off_hand
    client.player.off_hand
  end

  def swap_hands
    raise "Not implemented" # TODO send packet
  end

  # Moves the slot to the hotbar and selects it.
  # This is faster and less error-prone than doing these steps individually.
  def pick_slot(slot_nr : UInt16)
    raise "Not implemented" # TODO send packet
  end

  def start_using_item(hand = Hand::MainHand)
    raise "Not implemented" # TODO send packet
  end

  def stop_using_item
    raise "Not implemented" # TODO send packet
  end

  def digging_location : Vec3?
    nil # TODO
  end

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

  # add a callback processed upon specified incoming packet
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
