module Rosegold::Spectate::Configuration
  private def handle_client_information
    Log.debug { "Received client information (ignored — config already sent)" }
  end

  private def handle_finish_configuration
    Log.debug { "Configuration acknowledged, switching to play" }

    @protocol_state = ProtocolState::PLAY

    spawn do
      sleep 0.1.seconds
      enter_initial_state
    end
  end

  VANILLA_KNOWN_PACKS = {
    772_u32 => [{namespace: "minecraft", id: "core", version: "1.21.8"}],
    774_u32 => [{namespace: "minecraft", id: "core", version: "1.21.11"}],
  }

  private def send_configuration_packets
    if bot_known_packs = get_bot_known_packs
      send_packet(Rosegold::Clientbound::KnownPacks.new(bot_known_packs))
    else
      # Send vanilla known packs so client uses its built-in registry data
      vanilla_packs = VANILLA_KNOWN_PACKS[protocol_version]? || VANILLA_KNOWN_PACKS[774_u32]
      send_packet(Rosegold::Clientbound::KnownPacks.new(vanilla_packs))
    end
  end

  private def handle_known_packs_response(packet : Rosegold::Serverbound::KnownPacks)
    # Server must ALWAYS send RegistryData packets — entry names define numeric ID assignments.
    # Even if the client confirmed known packs (has the data locally), it still needs
    # the server to declare which entries exist and in what order.
    # We get this data from the bot's cached registries.
    bot_registries = get_bot_registries

    if bot_registries
      bot_registries.each do |_registry_id, registry_data|
        send_packet(registry_data)
      end

      if bot_update_tags = get_bot_update_tags
        send_packet(bot_update_tags)
      else
        send_packet(Rosegold::Clientbound::UpdateTags.new)
      end

      send_packet(Rosegold::Clientbound::FinishConfiguration.new)
    else
      Log.info { "No bot registries available, waiting for bot to connect..." }
      spawn do
        wait_for_bot_registries
      end
    end
  end

  private def wait_for_bot_registries
    loop do
      break unless @connected

      send_packet(Rosegold::Clientbound::ConfigurationKeepAlive.new(Time.utc.to_unix_ms))

      30.times do
        break unless @connected
        if (bot = @spectate_server.client) && bot.spawned?
          registries = bot.registries
          unless registries.empty?
            Log.info { "Bot connected, sending #{registries.size} registries to spectator" }

            registries.each do |_registry_id, registry_data|
              send_packet(registry_data)
            end

            if tags = bot.tags
              send_packet(tags)
            end

            send_packet(Rosegold::Clientbound::FinishConfiguration.new)
            return
          end
        end
        sleep 0.5.seconds
      end
    end
  end

  private def get_bot_registries : Hash(String, Rosegold::Clientbound::RegistryData)?
    bot = @client
    return nil unless bot

    registries = bot.registries
    return nil if registries.empty?

    registries
  end

  private def get_bot_known_packs : Array(NamedTuple(namespace: String, id: String, version: String))?
    bot = @client
    return nil unless bot

    known_packs = bot.known_packs
    return nil if known_packs.empty?

    known_packs
  end

  private def get_bot_update_tags : Rosegold::Clientbound::UpdateTags?
    bot = @client
    return nil unless bot

    bot.tags
  end
end
