module Rosegold::Spectate::Handshake
  private def handle_handshake(packet : Rosegold::Serverbound::Handshake)
    Log.debug { "Handshake: protocol=#{packet.protocol_version}, next_state=#{packet.next_state}" }

    @connected = true
    @handshake_protocol = packet.protocol_version

    case packet.next_state
    when 1 # Status
      @protocol_state = ProtocolState::STATUS
    when 2 # Login
      if packet.protocol_version != protocol_version
        @protocol_state = ProtocolState::LOGIN
        send_disconnect("Protocol version mismatch: server is #{protocol_version_name} (protocol #{protocol_version}), client sent #{packet.protocol_version}")
        return
      end
      @protocol_state = ProtocolState::LOGIN
    end
  end

  private def handle_login_start(packet : Rosegold::Serverbound::LoginStart)
    @username = packet.username
    @uuid = UUID.random

    Log.info { "Login start for #{@username}" }

    send_login_success
  end

  private def handle_login_acknowledged
    Log.debug { "Received Login Acknowledged, transitioning to configuration" }
    @protocol_state = ProtocolState::CONFIGURATION

    send_configuration_packets
  end

  private def handle_status_request
    Log.debug { "Received status request, sending server status" }

    online_players = client_ready? ? 1 : 0
    max_players = 1

    status_json = {
      "version" => {
        "name"     => protocol_version_name,
        "protocol" => protocol_version,
      },
      "players" => {
        "max"    => max_players,
        "online" => online_players,
        "sample" => [] of Hash(String, String),
      },
      "description" => {
        "text" => "Rosegold SpectateServer - #{client_ready? ? "Bot Connected" : "Waiting for Bot"}",
      },
    }.to_json

    response = Rosegold::Clientbound::StatusResponse.new(JSON.parse(status_json))
    send_packet(response)
    Log.debug { "Sent status response: #{online_players}/#{max_players} players" }
  end

  private def handle_status_ping(packet : Rosegold::Serverbound::StatusPing)
    Log.debug { "Received status ping, responding with pong" }

    pong = Rosegold::Clientbound::StatusPong.new(packet.ping_id)
    send_packet(pong)

    spawn do
      sleep 0.1.seconds
      close
    end
  end

  private def handle_keep_alive(packet : Rosegold::Serverbound::KeepAlive)
    Log.trace { "Received keep-alive response: #{packet.keep_alive_id}" }
  end

  private def send_login_success
    packet = Rosegold::Clientbound::LoginSuccess.new(@uuid, @username, [] of Rosegold::Clientbound::LoginSuccess::Property)
    send_packet(packet)
  end

  private def send_disconnect(reason : String)
    case @protocol_state
    when ProtocolState::LOGIN
      disconnect = Rosegold::Clientbound::LoginDisconnect.new(reason)
      send_packet(disconnect)
    when ProtocolState::CONFIGURATION
      disconnect = Rosegold::Clientbound::ConfigurationDisconnect.new(reason)
      send_packet(disconnect)
    when ProtocolState::PLAY
      disconnect = Rosegold::Clientbound::Disconnect.new(reason)
      send_packet(disconnect)
    else
      close
      return
    end

    spawn do
      sleep 0.1.seconds
      close
    end
  end
end
