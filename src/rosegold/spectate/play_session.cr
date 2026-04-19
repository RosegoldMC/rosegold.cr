module Rosegold::Spectate::PlaySession
  private def send_spectating_packets
    return unless bot = @client

    send_join_game(bot)
    send_set_time(bot)
    send_default_spawn_position(bot)
    send_player_abilities
    send_player_position(bot)
    send_update_health(bot)
    send_set_experience(bot)
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
    start_keep_alive_sender
  end

  private def send_join_game(bot : Rosegold::Client)
    packet = Rosegold::Clientbound::Login.new(
      entity_id: Server::DEFAULT_SPECTATOR_ENTITY_ID,
      hardcore: false,
      dimension_names: ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end"],
      max_players: 20_u32,
      view_distance: Server::DEFAULT_VIEW_DISTANCE,
      simulation_distance: Server::DEFAULT_SIMULATION_DISTANCE,
      reduced_debug_info: false,
      enable_respawn_screen: true,
      do_limited_crafting: false,
      dimension_type: bot.dimension.dimension_type,
      dimension_name: bot.dimension.name,
      hashed_seed: 0_i64,
      gamemode: 0_u8, # Survival for HUD
      previous_gamemode: -1_i8,
      is_debug: false,
      is_flat: false,
      has_death_location: false,
      death_dimension_name: nil,
      death_location: nil,
      portal_cooldown: 0_u32,
      sea_level: 63_u32,
      enforces_secure_chat: false
    )

    send_packet(packet)
  end

  private def send_lobby_join_game
    packet = Rosegold::Clientbound::Login.new(
      entity_id: Server::DEFAULT_SPECTATOR_ENTITY_ID,
      hardcore: false,
      dimension_names: ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end"],
      max_players: 20_u32,
      view_distance: Server::DEFAULT_VIEW_DISTANCE,
      simulation_distance: Server::DEFAULT_SIMULATION_DISTANCE,
      reduced_debug_info: false,
      enable_respawn_screen: true,
      do_limited_crafting: false,
      dimension_type: 0_u32,
      dimension_name: "minecraft:overworld",
      hashed_seed: 0_i64,
      gamemode: 3_u8, # Spectator for lobby (bypasses loading screen)
      previous_gamemode: -1_i8,
      is_debug: false,
      is_flat: false,
      has_death_location: false,
      death_dimension_name: nil,
      death_location: nil,
      portal_cooldown: 0_u32,
      sea_level: 63_u32,
      enforces_secure_chat: false
    )

    send_packet(packet)
  end

  private def send_set_time(bot : Rosegold::Client)
    packet = Rosegold::Clientbound::SetTime.new(
      world_age: bot.dimension.world_age,
      time_of_day: bot.dimension.time_of_day,
      tick_day_time: false
    )
    send_packet(packet)
  end

  private def send_default_spawn_position(bot : Rosegold::Client)
    pos = bot.player.feet
    spawn_pos = Vec3i.new(pos.x.to_i32, pos.y.to_i32, pos.z.to_i32)
    packet = Rosegold::Clientbound::SetDefaultSpawnPosition.new(spawn_pos, 0.0_f32, bot.dimension.name)
    send_packet(packet)
  end

  private def send_player_abilities
    packet = Rosegold::Clientbound::PlayerAbilities.new(
      0x06_u8,  # Flying allowed + currently flying
      0.05_f32, # Flying speed
      0.1_f32   # Field of view modifier
    )
    send_packet(packet)
  end

  private def send_player_position(bot : Rosegold::Client)
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
      bot.player.feet.x,
      bot.player.feet.y,
      bot.player.feet.z,
      bot.player.look.yaw,
      bot.player.look.pitch,
      0x00_u8,
      1_u32
    )

    send_packet(packet)
  end

  private def send_hotbar_selection(hotbar_nr : UInt32)
    packet = Rosegold::Clientbound::HeldItemChange.new(hotbar_nr)
    send_packet(packet)
  end

  private def send_inventory_content
    return unless bot = @client

    inventory = bot.inventory_menu
    slots = [] of WindowSlot

    (0...inventory.slots.size).each do |i|
      slot = inventory.slots[i]
      slots << WindowSlot.new(i, slot)
    end

    cursor_slot = WindowSlot.new(-1, inventory.cursor)

    safe_state_id = inventory.state_id
    packet = Rosegold::Clientbound::SetContainerContent.new(
      window_id: 0_u32,
      state_id: safe_state_id,
      slots: slots,
      cursor: cursor_slot
    )
    send_packet(packet)
    send_hotbar_selection(bot.player.hotbar_selection)
  end

  private def send_update_health(bot : Rosegold::Client)
    packet = Rosegold::Clientbound::UpdateHealth.new(
      bot.player.health,
      bot.player.food,
      bot.player.saturation
    )
    send_packet(packet)
  end

  private def send_set_experience(bot : Rosegold::Client)
    packet = Rosegold::Clientbound::SetExperience.new(
      bot.player.experience_progress,
      bot.player.experience_level,
      bot.player.total_experience
    )
    send_packet(packet)
  end

  private def send_start_waiting_for_chunks
    packet = Rosegold::Clientbound::GameEvent.start_waiting_for_chunks
    send_packet(packet)
    Log.debug { "Sent start waiting for chunks game event" }
  end

  private def start_keep_alive_sender
    return if @keep_alive_running
    @keep_alive_running = true
    spawn do
      loop do
        sleep Server::KEEP_ALIVE_INTERVAL
        break unless @connected
        @keep_alive_id = Time.utc.to_unix_ms
        keep_alive_packet = Rosegold::Clientbound::KeepAlive.new(@keep_alive_id)
        send_packet(keep_alive_packet)
      end
    rescue ex : IO::Error
      Log.debug { "Keep-alive connection closed: #{ex}" }
    rescue ex
      Log.error { "Keep-alive error: #{ex}" }
    ensure
      @keep_alive_running = false
    end
  end

  private def send_player_position_update(x : Float64, y : Float64, z : Float64, yaw : Float32, pitch : Float32)
    packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
      x, y, z, yaw, pitch,
      0x00_u8,
      @teleport_id &+= 1
    )
    send_packet(packet)
  end

  private def start_inventory_polling
    spawn do
      loop do
        send_inventory_content
        sleep Server::INVENTORY_POLL_INTERVAL
        break unless @connected
        break unless @spectate_state.spectating?
        break unless bot = @client
        break unless bot.connected?
      end
    rescue ex
      Log.debug { "Inventory polling error: #{ex}" }
    end
  end
end
