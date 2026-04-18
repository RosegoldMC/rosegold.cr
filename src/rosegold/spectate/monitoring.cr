struct Rosegold::Spectate::MonitorState
  property last_hotbar_selection : UInt32
  property last_chunk_x : Int32
  property last_chunk_z : Int32
  property last_dimension_name : String

  def initialize(@last_hotbar_selection, @last_chunk_x, @last_chunk_z, @last_dimension_name); end
end

module Rosegold::Spectate::Monitoring
  private def start_bot_monitoring
    return unless bot = @client

    spawn do
      monitor = MonitorState.new(
        last_hotbar_selection: bot.player.hotbar_selection,
        last_chunk_x: (bot.player.feet.x / 16).floor.to_i32,
        last_chunk_z: (bot.player.feet.z / 16).floor.to_i32,
        last_dimension_name: bot.dimension.name,
      )

      loop do
        break unless @connected
        break unless @spectate_state.spectating?

        unless bot.connected?
          transition_to_lobby("Bot disconnected. Waiting for reconnection...")
          break
        end

        sleep Server::BOT_MONITOR_INTERVAL

        check_dimension_change(monitor, bot)
        check_hotbar_updates(monitor, bot)
        check_chunk_updates(monitor, bot)
        track_block_breaking_progress(bot)
      end
    rescue e
      Log.error { "Bot monitoring error: #{e}" }
      Log.error exception: e
    end
  end

  private def check_dimension_change(monitor : MonitorState, bot : Rosegold::Client)
    current_dim = bot.dimension.name
    if current_dim != monitor.last_dimension_name
      Log.info { "Dimension changed: #{monitor.last_dimension_name} -> #{current_dim}" }
      handle_dimension_change(bot)
      monitor.last_dimension_name = current_dim
    end
  end

  private def handle_dimension_change(bot : Rosegold::Client)
    unload_all_chunks

    respawn = Rosegold::Clientbound::Respawn.new(
      dimension_type: bot.dimension.dimension_type,
      dimension_name: bot.dimension.name,
      hashed_seed: 0_i64,
      gamemode: 0_u8,
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

    send_player_abilities
    send_set_time(bot)

    send_default_spawn_position(bot)
    send_player_position(bot)
    send_start_waiting_for_chunks
    send_chunks
    send_existing_entities
    send_existing_entity_effects
    send_update_health(bot)
    send_inventory_content
  end

  private def check_hotbar_updates(monitor : MonitorState, bot : Rosegold::Client)
    current = bot.player.hotbar_selection
    if current != monitor.last_hotbar_selection
      send_hotbar_selection(current)
      monitor.last_hotbar_selection = current
    end
  end

  private def check_chunk_updates(monitor : MonitorState, bot : Rosegold::Client)
    current_x = (bot.player.feet.x / 16).floor.to_i32
    current_z = (bot.player.feet.z / 16).floor.to_i32

    if current_x != monitor.last_chunk_x || current_z != monitor.last_chunk_z
      update_chunks(current_x, current_z)
      monitor.last_chunk_x = current_x
      monitor.last_chunk_z = current_z
    end
  end

  private def track_block_breaking_progress(bot : Rosegold::Client)
    interactions = bot.interactions
    current_digging_block = interactions.digging_block
    current_dig_progress = interactions.block_damage_progress

    current_block_pos = current_digging_block.try(&.block)

    if current_block_pos != @last_digging_block
      if previous_block = @last_digging_block
        send_block_destroy_stage(bot.player.entity_id, previous_block, 255_u8)
      end

      @last_digging_block = current_block_pos
      @last_dig_progress = 0.0_f32

      if current_block_pos
        send_block_destroy_stage(bot.player.entity_id, current_block_pos, 0_u8)
      end
    end

    if current_block_pos && current_dig_progress != @last_dig_progress
      destroy_stage = (current_dig_progress * 9.0).clamp(0.0, 9.0).to_u8
      send_block_destroy_stage(bot.player.entity_id, current_block_pos, destroy_stage)
      @last_dig_progress = current_dig_progress.to_f32
    end

    if current_block_pos.nil? && @last_digging_block
      if previous_block = @last_digging_block
        send_block_destroy_stage(bot.player.entity_id, previous_block, 255_u8)
      end
      @last_digging_block = nil
      @last_dig_progress = 0.0_f32
    end
  end

  private def send_block_destroy_stage(entity_id, location : Vec3i, destroy_stage : UInt8)
    packet = Rosegold::Clientbound::SetBlockDestroyStage.new(entity_id.to_i32, location, destroy_stage)
    send_packet(packet)
  end
end
