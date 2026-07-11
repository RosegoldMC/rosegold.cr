module Rosegold::Spectate::SpectatorVehicle
  LOOK_TICK_DURATION = 50.milliseconds

  private def interaction_entity_type : UInt32?
    Rosegold::Entity.metadata_for_protocol.find { |meta| meta.name == "interaction" }.try(&.id.to_u32)
  end

  private def vehicle_y_offset : Float64
    Server::VEHICLE_PASSENGER_ATTACHMENT + (@vehicle_sneaking ? Server::SNEAK_CAMERA_DROP : 0.0)
  end

  private def mount_spectator_vehicle(bot : Rosegold::Client)
    entity_type = interaction_entity_type
    unless entity_type
      Log.warn { "Interaction entity type unavailable; spectator vehicle disabled" }
      return
    end

    @vehicle_sneaking = bot.player.sneaking?
    feet = bot.player.feet
    @last_bot_feet = feet
    @vehicle_uuid = UUID.random

    send_packet(Rosegold::Clientbound::SpawnEntity.new(
      entity_id: Server::SPECTATOR_VEHICLE_ENTITY_ID.to_u64,
      uuid: @vehicle_uuid,
      entity_type: entity_type,
      x: feet.x,
      y: feet.y - vehicle_y_offset,
      z: feet.z,
      pitch: 0.0,
      yaw: bot.player.look.yaw.to_f64,
      head_yaw: 0.0,
      data: 0_u32,
      velocity_x: 0.0,
      velocity_y: 0.0,
      velocity_z: 0.0
    ))

    send_packet(Rosegold::Clientbound::SetPassengers.new(
      Server::SPECTATOR_VEHICLE_ENTITY_ID.to_u32,
      [Server::DEFAULT_SPECTATOR_ENTITY_ID.to_u32]
    ))

    @vehicle_spawned = true

    reset_look_samples(bot.player.look)
    start_look_sender
  end

  private def destroy_spectator_vehicle
    return unless @vehicle_spawned
    @vehicle_spawned = false
    send_packet(Rosegold::Clientbound::DestroyEntities.new([Server::SPECTATOR_VEHICLE_ENTITY_ID.to_u64]))
  end

  private def update_vehicle_position(position : Vec3d, look : Look)
    return unless @vehicle_spawned
    send_packet(Rosegold::Clientbound::EntityPositionSync.new(
      entity_id: Server::SPECTATOR_VEHICLE_ENTITY_ID.to_u64,
      x: position.x,
      y: position.y - vehicle_y_offset,
      z: position.z,
      velocity_x: 0.0,
      velocity_y: 0.0,
      velocity_z: 0.0,
      yaw: look.yaw,
      pitch: 0.0_f32,
      on_ground: true
    ))
  end

  private def handle_spectator_position(position : Vec3d, look : Look)
    record_look_sample(look)

    previous = @last_bot_feet
    @last_bot_feet = position

    if @vehicle_spawned && previous && (position - previous).length > Server::TELEPORT_JUMP_THRESHOLD
      teleport_spectator_vehicle(position, look)
    else
      update_vehicle_position(position, look)
    end

    send_interpolated_look unless Server::LOOK_UPSAMPLING
  end

  private def teleport_spectator_vehicle(position : Vec3d, look : Look)
    return unless bot = @client
    send_packet(Rosegold::Clientbound::SetPassengers.new(
      Server::SPECTATOR_VEHICLE_ENTITY_ID.to_u32,
      [] of UInt32
    ))
    send_player_position_update(position.x, position.y, position.z, look.yaw, look.pitch)
    destroy_spectator_vehicle
    mount_spectator_vehicle(bot)
  end

  private def setup_sneak_listener
    track_bot_handler(Rosegold::Event::SneakChanged) do |event|
      next unless @connected
      next unless @spectate_state.spectating?
      next unless @vehicle_spawned
      @vehicle_sneaking = event.sneaking?
      if bot = @client
        update_vehicle_position(bot.player.feet, bot.player.look)
      end
    end
  end

  private def reset_look_samples(look : Look)
    @prev_look = look
    @last_look = look
    @last_look_time = Time.instant
  end

  private def record_look_sample(look : Look)
    @prev_look = @last_look || look
    @last_look = look
    @last_look_time = Time.instant
  end

  private def start_look_sender
    return unless Server::LOOK_UPSAMPLING
    return if @look_sender_running
    @look_sender_running = true
    spawn do
      loop do
        break unless @connected
        break unless @spectate_state.spectating?
        break unless @vehicle_spawned
        send_interpolated_look
        sleep Server::LOOK_UPDATE_INTERVAL
      end
    rescue ex : IO::Error
      Log.debug { "Look sender connection closed: #{ex}" }
    rescue ex
      Log.error { "Look sender error: #{ex}" }
    ensure
      @look_sender_running = false
    end
  end

  private def send_interpolated_look
    last = @last_look
    return unless last
    prev = @prev_look

    look = if prev && Server::LOOK_UPSAMPLING
             elapsed = (Time.instant - @last_look_time).total_milliseconds
             fraction = (elapsed / LOOK_TICK_DURATION.total_milliseconds).clamp(0.0, 1.0)
             interpolate_look(prev, last, fraction)
           else
             last
           end

    send_packet(Rosegold::Clientbound::PlayerRotation.new(look.yaw, look.pitch, false, false))
  end

  private def interpolate_look(from : Look, to : Look, fraction : Float64) : Look
    yaw = from.yaw + shortest_angle_delta(from.yaw, to.yaw) * fraction
    pitch = from.pitch + (to.pitch - from.pitch) * fraction
    Look.new(yaw.to_f32, pitch.to_f32)
  end

  private def shortest_angle_delta(from : Float32, to : Float32) : Float64
    ((to.to_f64 - from.to_f64 + 180.0) % 360.0) - 180.0
  end
end
