module Rosegold::Spectate::Lobby
  private def enter_initial_state
    if client_ready?
      @spectate_state = State::SPECTATING
      send_spectating_packets
    else
      @spectate_state = State::LOBBY
      send_lobby_packets
      start_lobby_monitor
    end
  end

  private def send_lobby_packets
    send_lobby_join_game

    # Position at (0, 100, 0)
    spawn_pos = Vec3i.new(0, 100, 0)
    send_packet(Rosegold::Clientbound::SetDefaultSpawnPosition.new(spawn_pos, 0.0_f32, "minecraft:overworld"))

    packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
      0.0, 100.0, 0.0,
      0.0_f32, 0.0_f32,
      0x00_u8, 1_u32
    )
    send_packet(packet)

    send_start_waiting_for_chunks

    # Send single empty chunk at (0, 0)
    send_packet(Rosegold::Clientbound::SetChunkCacheCenter.new(0, 0))
    send_empty_chunk(0, 0)

    # System chat message
    send_packet(Rosegold::Clientbound::SystemChatMessage.new(TextComponent.new("Waiting for bot to connect..."), false))

    start_keep_alive_sender
  end

  private def start_lobby_monitor
    spawn do
      loop do
        break unless @connected
        break unless @spectate_state.lobby?

        if client_ready?
          transition_to_spectating
          break
        end

        sleep 0.5.seconds
      end
    rescue e
      Log.error { "Lobby monitor error: #{e}" }
    end
  end

  private def transition_to_spectating
    @transition_mutex.synchronize do
      return unless @spectate_state.lobby?
      return unless client_ready?
      return unless bot = @spectate_server.client

      Log.info { "Transitioning #{@username} from lobby to spectating" }

      @client = bot

      # Send Respawn to transition from spectator (lobby) to survival (spectating)
      respawn = Rosegold::Clientbound::Respawn.new(
        dimension_type: bot.dimension.dimension_type,
        dimension_name: bot.dimension.name,
        hashed_seed: 0_i64,
        gamemode: 0_u8, # Survival for HUD
        previous_gamemode: 3_i8,
        is_debug: false,
        is_flat: false,
        has_death_location: false,
        death_dimension_name: nil,
        death_location: nil,
        portal_cooldown: 0_u32,
        sea_level: 63_u32,
        data_kept: 0_u8
      )
      send_packet(respawn)

      @spectate_state = State::SPECTATING

      # Unload lobby chunk
      send_packet(Rosegold::Clientbound::UnloadChunk.new(0, 0))

      send_player_abilities
      send_default_spawn_position(bot)
      send_player_position(bot)
      send_set_time(bot)
      send_update_health(bot)
      start_inventory_polling
      send_hotbar_selection(bot.player.hotbar_selection)
      send_start_waiting_for_chunks
      send_chunks
      send_existing_players
      send_existing_entities
      send_existing_entity_effects
      start_bot_monitoring
      setup_position_event_listener
      setup_arm_swing_listener
      setup_container_closed_listener
      setup_raw_packet_relay

      Log.info { "#{@username} is now spectating" }
    end
  end

  private def transition_to_lobby(message : String = "Bot disconnected. Waiting for reconnection...")
    @transition_mutex.synchronize do
      return unless @spectate_state.spectating?

      Log.info { "Transitioning #{@username} from spectating to lobby" }

      cleanup_event_handlers

      # Unload all world state
      unload_all_chunks
      destroy_all_entities

      @client = nil

      # Send Respawn to transition to spectator mode (lobby)
      respawn = Rosegold::Clientbound::Respawn.new(
        dimension_type: 0_u32,
        dimension_name: "minecraft:overworld",
        hashed_seed: 0_i64,
        gamemode: 3_u8, # Spectator for lobby
        previous_gamemode: 0_i8,
        is_debug: false,
        is_flat: false,
        has_death_location: false,
        death_dimension_name: nil,
        death_location: nil,
        portal_cooldown: 0_u32,
        sea_level: 63_u32,
        data_kept: 0_u8
      )
      send_packet(respawn)

      @spectate_state = State::LOBBY

      spawn_pos = Vec3i.new(0, 100, 0)
      send_packet(Rosegold::Clientbound::SetDefaultSpawnPosition.new(spawn_pos, 0.0_f32, "minecraft:overworld"))

      packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
        0.0, 100.0, 0.0,
        0.0_f32, 0.0_f32,
        0x00_u8, 1_u32
      )
      send_packet(packet)

      send_start_waiting_for_chunks
      send_packet(Rosegold::Clientbound::SetChunkCacheCenter.new(0, 0))
      send_empty_chunk(0, 0)

      send_packet(Rosegold::Clientbound::SystemChatMessage.new(TextComponent.new(message), false))

      start_lobby_monitor

      Log.info { "#{@username} is now in lobby" }
    end
  end

  # Build a minimal all-air chunk
  private def send_empty_chunk(chunk_x : Int32, chunk_z : Int32)
    section_io = Minecraft::IO::Memory.new

    # 24 sections for overworld (-64 to 320, height 384)
    # Each section: block_count (raw Int16) + blocks PalettedContainer + biomes PalettedContainer
    # Single-state PalettedContainer: bits_per_entry=0 (byte), palette_entry (varint), data_array_length=0 (varint)
    24.times do
      section_io.write_full 0_i16 # block count = 0 (raw big-endian Int16)
      section_io.write 0_u8       # blocks: bits per entry = 0 (single state)
      section_io.write 0_u32      # blocks: palette entry = air (block state 0, varint)
      section_io.write 0_u32      # blocks: data array length = 0
      section_io.write 0_u8       # biomes: bits per entry = 0 (single state)
      section_io.write 0_u32      # biomes: palette entry = 0 (varint)
      section_io.write 0_u32      # biomes: data array length = 0
    end
    chunk_data = section_io.to_slice

    pkt_io = Minecraft::IO::Memory.new
    pkt_io.write Rosegold::Clientbound::ChunkData.packet_id_for_protocol(Client.protocol_version)
    pkt_io.write_full chunk_x
    pkt_io.write_full chunk_z

    # Heightmaps: 0 entries
    pkt_io.write 0_u32

    # Chunk section data
    pkt_io.write chunk_data.size
    pkt_io.write chunk_data

    # Block entities: 0
    pkt_io.write 0_u32

    # Light data: empty (sky light mask, block light mask, empty sky light mask, empty block light mask, sky lights, block lights)
    # All zeros for BitSets and arrays
    6.times { pkt_io.write 0_u32 }

    raw = pkt_io.to_slice
    raw_packet = Rosegold::Clientbound::RawPacket.new(raw)
    send_packet(raw_packet)
  end
end
