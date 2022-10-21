class Rosegold::Bot
  getter client : Rosegold::Client

  def initialize(@client)
  end

  # retrieve the pitch the player is looking
  delegate on, to: client

  forward_missing_to client.player

  # send a message or slash command
  def chat(message : String)
    client.queue_packet Rosegold::Serverbound::Chat.new message
  end

  # queue a jump to the physics engine
  def start_jump
    client.physics.jump_queued = true
  end

  # Use to move the player to a location, does not take into account y (height)
  # moves bluntly without avoiding obstructions to comply with Civ botting rules
  def move_to(location : Vec3d)
    client.physics.move location
  end

  # :ditto:
  def move_to(x, y, z)
    move_to Vec3d.new x, y, z
  end

  # :ditto:
  def move_to(x, z)
    move_to x, feet.y, z
  end

  # :ditto:
  def look_by(look : Look)
    client.physics.look look
  end

  # add a callback processed upon specified incoming packet
  #
  # ```
  # client.on_packet Rosegold::Clientbound::Chat do |chat|
  #   puts "Received chat: #{chat.message}"
  # end
  # ```
  def on(packet_type : T.class, &block : T ->) forall T
    client.on packet_type, &block
  end
end
