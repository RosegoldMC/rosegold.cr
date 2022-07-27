class Rosegold::Bot
  getter client : Rosegold::Client

  def initialize(@client)
  end

  # Used to send a message or / command
  def chat(message : String)
    client.queue_packet Rosegold::Serverbound::Chat.new message
  end

  # Used to queue a jump to the physics engine
  def jump
    client.physics.jump_queued = true
  end

  # Used to set the pitch the player is looking
  def pitch=(angle)
    player.look.pitch = angle
  end

  delegate pitch, to: player.look

  # Used to set the yaw the player is looking
  def yaw=(angle)
    player.look.yaw = angle
  end

  delegate yaw, to: player.look

  # Use to move the player to a location, does not take into account y (height)
  # moves bluntly without avoiding obstructions to comply with Civ botting rules
  def move_to(x, y, z)
    client.physics.movement_target = Vec3d.new x, y, z
  end

  # :ditto:
  def move_to(x, z)
    move_to x, player.position.y, z
  end

  forward_missing_to client
end
