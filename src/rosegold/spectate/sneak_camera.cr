module Rosegold::Spectate::SneakCamera
  # Client eye height is 1.62 * scale, so this lands the camera at the bot's 1.27 sneaking eye.
  SNEAK_EYE_SCALE = 1.27 / 1.62

  # minecraft:scale registry index per protocol, from Attributes.java registration order (shifted in 26.2).
  SCALE_ATTRIBUTE_IDS = {
    772_u32 => 25_u32,
    773_u32 => 25_u32,
    774_u32 => 25_u32,
    775_u32 => 25_u32,
    776_u32 => 30_u32,
  }

  private def setup_sneak_listener
    track_bot_handler(Rosegold::Event::SneakChanged) do |event|
      next unless @connected
      next unless @spectate_state.spectating?
      send_spectator_scale(event.sneaking? ? SNEAK_EYE_SCALE : 1.0)
    end
  end

  private def send_current_sneak_scale(bot : Rosegold::Client)
    send_spectator_scale(bot.player.sneaking? ? SNEAK_EYE_SCALE : 1.0)
  end

  private def send_spectator_scale(scale : Float64)
    pkt_id = Server::UNIMPLEMENTED_FORWARDED["update_attributes"][protocol_version]?
    attribute_id = SCALE_ATTRIBUTE_IDS[protocol_version]?
    unless pkt_id && attribute_id
      Log.debug { "Sneak camera scale unsupported for protocol #{protocol_version}" }
      return
    end

    io = Minecraft::IO::Memory.new
    io.write pkt_id
    io.write Server::DEFAULT_SPECTATOR_ENTITY_ID.to_u32
    io.write 1_u32
    io.write attribute_id
    io.write_full scale
    io.write 0_u32
    send_packet(Rosegold::Clientbound::RawPacket.new(io.to_slice))
  end
end
