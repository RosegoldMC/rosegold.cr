module Rosegold::Spectate::LookSmoothing
  LOOK_TICK_DURATION = 50.milliseconds
  # SynchronizePlayerPosition relative flags: yaw 0x08, pitch 0x10.
  RELATIVE_ROTATION_FLAGS = 0x18

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

    look = if prev
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
