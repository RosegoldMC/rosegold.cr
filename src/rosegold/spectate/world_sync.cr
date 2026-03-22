module Rosegold::Spectate::WorldSync
  private def send_chunks
    return unless bot = @client

    player_chunk_x = (bot.player.feet.x / 16).floor.to_i32
    player_chunk_z = (bot.player.feet.z / 16).floor.to_i32

    packet = Rosegold::Clientbound::SetChunkCacheCenter.new(player_chunk_x, player_chunk_z)
    send_packet(packet)

    view_distance = Server::DEFAULT_RENDER_DISTANCE
    chunks_sent = 0

    send_packet(Rosegold::Clientbound::ChunkBatchStart.new)
    (-view_distance..view_distance).each do |delta_x|
      (-view_distance..view_distance).each do |delta_z|
        chunk_x = player_chunk_x + delta_x
        chunk_z = player_chunk_z + delta_z

        if send_chunk_data(chunk_x, chunk_z)
          @loaded_chunks.add({chunk_x, chunk_z})
          chunks_sent += 1
        end
      end
    end
    send_packet(Rosegold::Clientbound::ChunkBatchFinished.new(chunks_sent.to_i32))
  end

  private def update_chunks(chunk_x : Int32, chunk_z : Int32)
    center_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(chunk_x, chunk_z)
    send_packet(center_packet)

    render_distance = Server::DEFAULT_RENDER_DISTANCE

    chunks_to_unload = @loaded_chunks.select do |loaded_chunk_x, loaded_chunk_z|
      distance_x = (loaded_chunk_x - chunk_x).abs
      distance_z = (loaded_chunk_z - chunk_z).abs
      distance_x > render_distance || distance_z > render_distance
    end

    chunks_to_unload.each do |old_chunk_x, old_chunk_z|
      unload_packet = Rosegold::Clientbound::UnloadChunk.new(old_chunk_x, old_chunk_z)
      send_packet(unload_packet)
      @loaded_chunks.delete({old_chunk_x, old_chunk_z})
    end

    chunks_to_load = [] of Tuple(Int32, Int32)

    (-render_distance..render_distance).each do |delta_x|
      (-render_distance..render_distance).each do |delta_z|
        new_chunk_x = chunk_x + delta_x
        new_chunk_z = chunk_z + delta_z
        chunk_pos = {new_chunk_x, new_chunk_z}

        next if @loaded_chunks.includes?(chunk_pos)
        chunks_to_load << chunk_pos
      end
    end

    if chunks_to_load.size > 0
      send_packet(Rosegold::Clientbound::ChunkBatchStart.new)
      successfully_loaded = 0
      chunks_to_load.each do |load_chunk_x, load_chunk_z|
        if send_chunk_data(load_chunk_x, load_chunk_z)
          @loaded_chunks.add({load_chunk_x, load_chunk_z})
          successfully_loaded += 1
        end
      end
      send_packet(Rosegold::Clientbound::ChunkBatchFinished.new(successfully_loaded.to_i32))
    end
  end

  private def send_chunk_data(chunk_x : Int32, chunk_z : Int32) : Bool
    return false unless bot = @client

    chunk = bot.dimension.chunk_at?(chunk_x, chunk_z)

    if chunk
      chunk_packet = Rosegold::Clientbound::ChunkData.new(chunk)
      send_packet(chunk_packet)
      true
    else
      false
    end
  end

  private def unload_all_chunks
    @loaded_chunks.each do |chunk_x, chunk_z|
      unload_packet = Rosegold::Clientbound::UnloadChunk.new(chunk_x, chunk_z)
      send_packet(unload_packet)
    end
    @loaded_chunks.clear
  end

  private def send_existing_entities
    return unless bot = @client

    entity_count = 0
    bot.dimension.entities.each do |entity_id, entity|
      spawn_packet = Rosegold::Clientbound::SpawnEntity.new(
        entity_id: entity_id.to_u32, # Minecraft entity IDs fit in VarInt (32-bit)
        uuid: entity.uuid,
        entity_type: entity.entity_type,
        x: entity.position.x,
        y: entity.position.y,
        z: entity.position.z,
        pitch: entity.pitch.to_f64,
        yaw: entity.yaw.to_f64,
        head_yaw: entity.head_yaw.to_f64,
        data: 0_u32,
        velocity_x: entity.velocity.x,
        velocity_y: entity.velocity.y,
        velocity_z: entity.velocity.z
      )

      send_packet(spawn_packet)
      entity_count += 1
    end

    Log.info { "Sent #{entity_count} existing entities to spectator #{@username}" }
  end

  private def send_existing_entity_effects
    return unless bot = @client

    effect_count = 0

    bot.player.effects.each do |effect|
      Log.debug { "Sending existing effect #{effect.id} (amplifier #{effect.amplifier}, duration #{effect.duration}) to spectator #{@username}" }
      effect_packet = Rosegold::Clientbound::EntityEffect.new(
        Server::DEFAULT_SPECTATOR_ENTITY_ID.to_u64,
        effect.id.to_u32,
        effect.amplifier.to_u32,
        effect.duration.to_u32,
        effect.flags.to_u8
      )
      send_packet(effect_packet)
      effect_count += 1
    end

    Log.info { "Sent #{effect_count} existing player effects to spectator #{@username}" }
  end

  private def send_existing_players
    return unless bot = @client

    if bot.player_list.size > 0
      all_players = bot.player_list.values.compact_map do |entry|
        next unless entry.name

        properties = entry.properties.map do |prop|
          Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry::Property.new(
            prop.name, prop.value, prop.signature
          )
        end

        Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(
          uuid: entry.uuid,
          name: entry.name,
          properties: properties,
          gamemode: entry.gamemode.try(&.to_i32) || 0,
          listed: true,
          latency: entry.ping.try(&.to_i32) || 0,
          display_name: entry.display_name
        )
      end

      if all_players.size > 0
        actions = Rosegold::Clientbound::PlayerInfoUpdate::ADD_PLAYER |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_GAMEMODE |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LISTED |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY

        player_info_packet = Rosegold::Clientbound::PlayerInfoUpdate.new(actions, all_players)
        send_packet(player_info_packet)

        Log.info { "Sent info for #{all_players.size} existing players to spectator #{@username}" }
      end
    end
  end

  private def destroy_all_entities
    return unless bot = @client

    entity_ids = bot.dimension.entities.keys.map(&.to_u64)
    return if entity_ids.empty?

    destroy_packet = Rosegold::Clientbound::DestroyEntities.new(entity_ids)
    send_packet(destroy_packet)
  end
end
