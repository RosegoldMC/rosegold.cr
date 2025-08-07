require "socket"
require "./events/*"
require "./packets/*"
require "./world/*"
require "../minecraft/nbt"

# Forward declaration to avoid circular dependency
class Rosegold::Client; end

# A spectate server that allows Minecraft clients to connect and spectate a rosegold bot
class Rosegold::SpectateServer
  property host : String
  property port : Int32
  property bot : Rosegold::Client?
  property server : TCPServer?
  private property connections = Array(SpectateConnection).new
  private property lockout_active = false

  # World state mirrored from the bot
  property dimension : Dimension = Dimension.new
  property bot_player : Player = Player.new
  property entities : Hash(UInt32, Entity) = Hash(UInt32, Entity).new

  Log = ::Log.for(self)

  def initialize(@host : String = "127.0.0.1", @port : Int32 = 25566)
  end

  def start
    @server = TCPServer.new(host, port)
    Log.info { "Spectate server listening on #{host}:#{port}" }

    spawn do
      while server = @server
        begin
          client_socket = server.accept
          Log.info { "New client connection from #{client_socket.remote_address}" }

          connection = SpectateConnection.new(client_socket, self)
          @connections << connection

          spawn do
            connection.handle_client
          rescue e
            Log.error { "Client connection error: #{e}" }
          ensure
            @connections.delete(connection)
          end
        rescue e : IO::Error
          Log.debug { "Server accept error: #{e}" }
          break
        end
      end
    end
  end

  def stop
    @server.try(&.close)
    @server = nil
    @connections.each(&.disconnect("Server shutting down"))
    @connections.clear
  end

  def attach_bot(bot : Rosegold::Client)
    @bot = bot
    Log.info { "Bot attached to proxy server" }
  end

  def detach_bot
    @bot = nil
    Log.info { "Bot detached from proxy server" }
  end

  def enable_lockout
    @lockout_active = true
    Log.info { "Client lockout enabled - bot is in control" }
    @connections.each(&.send_lockout_message)
  end

  def disable_lockout
    @lockout_active = false
    Log.info { "Client lockout disabled - clients can control bot" }
    @connections.each(&.send_unlock_message)
  end

  def lockout_active?
    @lockout_active
  end

  def bot_connected?
    bot = @bot
    return false unless bot
    bot.connected? || false
  end

  # Forward a packet from client to the bot/server
  def forward_to_server(packet_bytes : Bytes, from_connection : SpectateConnection)
    return unless bot_connected? && !lockout_active?

    begin
      if bot = @bot
        # Send raw packet bytes directly to the bot's connection
        bot.connection.try(&.send_packet(packet_bytes))
      end
    rescue e
      Log.error { "Failed to forward packet to server: #{e}" }
    end
  end

  # Handle chat interception for custom commands
  def intercept_chat(message : String, from_connection : SpectateConnection?) : Bool
    if message.starts_with?("/rosegold")
      handle_rosegold_command(message, from_connection)
      return true
    end

    false # Let other chat messages pass through
  end

  private def handle_rosegold_command(command : String, connection : SpectateConnection?)
    args = command.split(" ")[1..]

    case args[0]?
    when "status"
      status_message = if bot_connected?
                         if lockout_active?
                           "§aBOT ACTIVE§r - Bot is controlling the player. Type §6/rosegold unlock§r to take control."
                         else
                           "§2BOT CONNECTED§r - You can control the bot. Type §6/rosegold lock§r to let bot take control."
                         end
                       else
                         "§cBOT DISCONNECTED§r - No bot is currently connected."
                       end
      connection.try(&.send_chat_message(status_message))
    when "lock"
      if bot_connected?
        enable_lockout
        connection.try(&.send_chat_message("§6Bot lockout enabled§r - Bot is now in control"))
      else
        connection.try(&.send_chat_message("§cNo bot connected§r"))
      end
    when "unlock"
      if bot_connected?
        disable_lockout
        connection.try(&.send_chat_message("§aClient control enabled§r - You can now control the bot"))
      else
        connection.try(&.send_chat_message("§cNo bot connected§r"))
      end
    when "help", nil
      help_text = [
        "§6Rosegold Proxy Commands:",
        "§7/rosegold status §f- Show bot and lockout status",
        "§7/rosegold lock §f- Enable bot lockout (bot controls)",
        "§7/rosegold unlock §f- Disable bot lockout (client controls)",
        "§7/rosegold help §f- Show this help message",
      ]
      connection.try { |conn| help_text.each { |line| conn.send_chat_message(line) } }
    else
      connection.try(&.send_chat_message("§cUnknown command. Use §6/rosegold help§c for available commands."))
    end
  end

  # === World State Management ===

  # Update chunk data from the bot
  def update_chunk(chunk : Chunk)
    @dimension.load_chunk(chunk)
    Log.debug { "Updated chunk (#{chunk.x}, #{chunk.z}) in spectate server" }

    # Send chunk to all connected spectate clients
    send_chunk_to_all_clients(chunk)
  end

  # Update player position from the bot
  def update_player_position(position : Vec3d, look : Look)
    @bot_player.feet = position
    @bot_player.look = look
    Log.trace { "Updated bot player position: #{position} look: #{look}" }

    # Send position update to all spectate clients
    send_player_position_to_all_clients(position, look)
  end

  # Update entity from the bot
  def update_entity(entity : Entity)
    @entities[entity.entity_id] = entity
    Log.trace { "Updated entity #{entity.entity_id} in spectate server" }

    # Send entity update to all spectate clients
    send_entity_to_all_clients(entity)
  end

  # Remove entity from the bot
  def remove_entity(entity_id : UInt64)
    @entities.delete(entity_id)
    Log.trace { "Removed entity #{entity_id} from spectate server" }

    # Send entity removal to all spectate clients
    send_entity_removal_to_all_clients(entity_id)
  end

  private def send_chunk_to_all_clients(chunk : Chunk)
    return if @connections.empty?

    begin
      chunk_packet = Clientbound::ChunkData.new(chunk)
      packet_bytes = chunk_packet.write

      @connections.each do |spectate_connection|
        conn = spectate_connection.connection
        spectate_connection.send_packet(packet_bytes) if conn && conn.protocol_state == ProtocolState::PLAY
      end

      Log.debug { "Sent chunk (#{chunk.x}, #{chunk.z}) to #{@connections.size} spectate clients" }
    rescue e
      Log.error { "Failed to send chunk (#{chunk.x}, #{chunk.z}) to spectate clients: #{e}" }
    end
  end

  private def send_player_position_to_all_clients(position : Vec3d, look : Look)
    return if @connections.empty?

    begin
      # Send entity position sync packet to show bot movement to spectating clients
      bot = @bot
      return unless bot

      # Generate consistent entity ID based on bot name (VarInt compatible)
      bot_name = bot.offline.try(&.[:username]) || "SpectateBot"
      bot_entity_id = (1000 + (bot_name.hash.abs % 10000)).to_u32

      # Create entity position sync packet for the bot player entity
      position_sync_packet = Clientbound::EntityPositionSync.new(
        entity_id: bot_entity_id.to_u32,
        x: position.x,
        y: position.y,
        z: position.z,
        velocity_x: 0.0,
        velocity_y: 0.0,
        velocity_z: 0.0,
        yaw: look.yaw,
        pitch: look.pitch,
        on_ground: true
      )

      # Send to all spectating clients
      @connections.each do |spectate_conn|
        next unless spectate_conn.connection.try(&.protocol_state) == ProtocolState::PLAY
        begin
          spectate_conn.send_packet(position_sync_packet)
        rescue e
          Log.warn { "Failed to send entity position sync to client #{spectate_conn}: #{e}" }
        end
      end

      Log.trace { "Sent bot entity position sync to #{@connections.size} spectate clients: #{position} look: #{look}" }
    rescue e
      Log.error { "Failed to send player position to spectate clients: #{e}" }
    end
  end

  private def send_entity_to_all_clients(entity : Entity)
    return if @connections.empty?

    begin
      # Create appropriate entity spawn packet based on entity type
      # For now, assume it's a living entity - proper implementation would check entity type
      spawn_packet = Clientbound::SpawnLivingEntity.new(
        entity.entity_id,
        entity.uuid,
        entity.entity_type,
        entity.position.x,
        entity.position.y,
        entity.position.z,
        entity.pitch.to_f64,
        entity.yaw.to_f64,
        entity.head_yaw.to_f64,
        0_u32, # data
        (entity.velocity.x * 8000).to_i16,
        (entity.velocity.y * 8000).to_i16,
        (entity.velocity.z * 8000).to_i16
      )

      packet_bytes = spawn_packet.write

      # log packet_bytes
      Log.info { "Sending entity #{entity.entity_id} spawn packet: #{packet_bytes.inspect}" }

      @connections.each do |spectate_connection|
        conn = spectate_connection.connection
        spectate_connection.send_packet(packet_bytes) if conn && conn.protocol_state == ProtocolState::PLAY
      end

      Log.trace { "Sent entity #{entity.entity_id} spawn to #{@connections.size} spectate clients" }
    rescue e
      Log.error { "Failed to send entity #{entity.entity_id} to spectate clients: #{e}" }
    end
  end

  private def send_entity_removal_to_all_clients(entity_id : UInt64)
    return if @connections.empty?

    begin
      destroy_packet = Clientbound::DestroyEntities.new([entity_id])
      packet_bytes = destroy_packet.write

      @connections.each do |spectate_connection|
        conn = spectate_connection.connection
        spectate_connection.send_packet(packet_bytes) if conn && conn.protocol_state == ProtocolState::PLAY
      end

      Log.trace { "Sent entity removal #{entity_id} to #{@connections.size} spectate clients" }
    rescue e
      Log.error { "Failed to send entity removal #{entity_id} to spectate clients: #{e}" }
    end
  end
end

# Handles an individual client connection to the spectate server
class Rosegold::SpectateConnection
  property socket : TCPSocket
  property proxy : SpectateServer
  property connection : Connection::Server?
  property protocol_version : UInt32 = 0_u32
  property username : String = ""

  Log = ::Log.for(self)

  def initialize(@socket : TCPSocket, @proxy : SpectateServer)
  end

  def handle_client
    io = Minecraft::IO::Wrap.new(@socket)
    @connection = Connection::Server.new(io, ProtocolState::HANDSHAKING, Client.protocol_version)

    Log.debug { "Starting client handler loop" }

    loop do
      break unless connection = @connection

      Log.trace { "Reading packet in state: #{connection.protocol_state.name}" }
      packet_bytes = connection.read_raw_packet

      # Get packet ID to determine if we need to handle it specially
      packet_id = packet_bytes[0]?
      Log.trace { "Received packet ID: 0x#{packet_id.try(&.to_s(16).upcase.rjust(2, '0')) || "??"} in state #{connection.protocol_state.name}" }

      # Only try to decode packets we know we need to handle specially
      # For all others, just forward the raw bytes to avoid parsing issues
      packet = if should_handle_packet_specially?(packet_id, connection.protocol_state)
                 begin
                   Connection.decode_serverbound_packet(packet_bytes, connection.protocol_state, connection.protocol_version)
                 rescue e
                   Log.warn { "Failed to parse packet 0x#{packet_id.try(&.to_s(16).upcase.rjust(2, '0'))}: #{e}" }
                   Log.warn { "Falling back to raw packet forwarding" }
                   Serverbound::RawPacket.new(packet_bytes)
                 end
               else
                 Serverbound::RawPacket.new(packet_bytes)
               end

      Log.trace { "Handled packet: #{packet.class}" }

      case packet
      when Serverbound::Handshake
        handle_handshake(packet)
      when Serverbound::StatusRequest
        handle_status_request
      when Serverbound::StatusPing
        handle_status_ping(packet)
      when Serverbound::LoginStart
        handle_login_start(packet)
      when Serverbound::LoginAcknowledged
        handle_login_acknowledged(packet)
      when Serverbound::FinishConfiguration
        handle_finish_configuration(packet)
      when Serverbound::ChatMessage
        # Only handle chat in PLAY state
        if connection.protocol_state == ProtocolState::PLAY
          handle_chat(packet, packet_bytes)
        else
          Log.trace { "Ignoring chat message in #{connection.protocol_state.name} state" }
        end
      when Serverbound::RawPacket
        # No longer forward raw packets - spectate server is read-only
        packet_id_hex = packet_bytes[0]?.try(&.to_s(16).upcase.rjust(2, '0')) || "??"
        Log.trace { "Received raw packet 0x#{packet_id_hex} from spectate client (not forwarding)" }
      else
        # No longer forward packets to server - spectate server is read-only
        packet_id_hex = packet_bytes[0]?.try(&.to_s(16).upcase.rjust(2, '0')) || "??"
        Log.trace { "Received packet 0x#{packet_id_hex}: #{packet.class} from spectate client (not forwarding)" }
      end
    end
  rescue e : IO::Error
    Log.debug { "Client disconnected: #{e}" }
  rescue e
    Log.error { "Client handling error: #{e}" }
    Log.error { "Stack trace: #{e.backtrace?.try(&.join("\n"))}" }
  ensure
    disconnect
  end

  private def handle_handshake(packet : Serverbound::Handshake)
    @protocol_version = packet.protocol_version

    if connection = @connection
      case packet.next_state
      when 1 # Status
        connection.protocol_state = ProtocolState::STATUS
      when 2 # Login
        connection.protocol_state = ProtocolState::LOGIN
      end
    end
  end

  private def handle_status_request
    # Respond with proxy server status
    status_response = {
      "version" => {
        "name"     => "Rosegold Proxy",
        "protocol" => @protocol_version,
      },
      "players" => {
        "max"    => 1,
        "online" => @proxy.bot_connected? ? 1 : 0,
        "sample" => [] of String,
      },
      "description" => {
        "text" => "Rosegold Spectate Server (1.21.8)",
      },
    }

    send_packet(Clientbound::StatusResponse.new(JSON.parse(status_response.to_json)))
  end

  private def handle_status_ping(packet : Serverbound::StatusPing)
    send_packet(Clientbound::StatusPong.new(packet.ping_id))
  end

  private def handle_login_start(packet : Serverbound::LoginStart)
    @username = packet.username

    # Send login success
    uuid = UUID.random
    send_packet(Clientbound::LoginSuccess.new(uuid, @username, [] of Clientbound::LoginSuccess::Property))

    # For protocol 767+ (MC 1.21+), we don't change state yet - client will send LoginAcknowledged
    if connection = @connection
      if @protocol_version < 767
        connection.protocol_state = ProtocolState::PLAY
        Log.debug { "Transitioned directly to PLAY state" }
      end
      # For newer protocols, state transition happens in handle_login_acknowledged
    end

    Log.info { "Client #{@username} logged in" }

    # For older protocols, send welcome messages immediately
    # For newer protocols, messages will be sent after configuration finishes
    if @protocol_version < 767
      send_chat_message("§6Welcome to Rosegold Proxy!§r Type §a/rosegold help§r for commands.")

      if @proxy.bot_connected?
        if @proxy.lockout_active?
          send_lockout_message
        else
          send_chat_message("§2Bot connected§r - You can control the bot")
        end
      else
        send_chat_message("§cNo bot connected§r - Waiting for bot connection...")
      end
    end
  end

  private def handle_login_acknowledged(packet : Serverbound::LoginAcknowledged)
    Log.debug { "Client acknowledged login, transitioning to CONFIGURATION state" }
    if connection = @connection
      connection.protocol_state = ProtocolState::CONFIGURATION

      # Send necessary configuration packets including registry data
      send_configuration_packets
    end
  end

  private def handle_finish_configuration(packet : Serverbound::FinishConfiguration)
    Log.debug { "Client finished configuration, transitioning to PLAY state" }
    if connection = @connection
      connection.protocol_state = ProtocolState::PLAY
    end

    Log.info { "Client #{@username} is now in PLAY state and ready for packet forwarding" }

    if @proxy.bot_connected?
      # Bot is connected - send essential PLAY state packets using bot's current state
      Log.info { "Bot connected - sending essential PLAY state packets to client" }

      spawn do
        send_essential_play_packets
      end
    else
      # No bot connected - send disconnect packet instead of letting client crash
      Log.warn { "No bot connected - sending proper disconnect" }

      # Send disconnect packet immediately to avoid client crashes
      disconnect_packet = Clientbound::Disconnect.new(
        Chat.new("§cProxy Error\n\n§7No bot server is connected to this proxy.\n§7Please connect a bot to a Minecraft server first.")
      )
      send_packet(disconnect_packet)

      # Close connection after a brief delay
      spawn do
        sleep 0.1.seconds
        disconnect("No bot server available")
      end
    end
  end

  private def send_welcome_messages_if_standalone
    # Only send messages if we're in standalone mode (no bot connected)
    unless @proxy.bot_connected?
      send_chat_message("§6Welcome to Rosegold Proxy!§r")
      send_chat_message("§cNo bot connected§r - Connect a bot to use the proxy")
      send_chat_message("§7Use §a/rosegold help§7 for commands")
    end
  end

  private def handle_chat(packet : Serverbound::ChatMessage, packet_bytes : Bytes)
    # Check for custom commands first
    if @proxy.intercept_chat(packet.message, self)
      return # Command was handled
    end

    # No longer forward chat to server - spectate server is read-only
    Log.trace { "Received chat message from spectate client: #{packet.message} (not forwarding)" }
  end

  def send_packet(packet : Clientbound::Packet)
    connection.try(&.send_packet(packet))
  end

  def send_packet(packet_bytes : Bytes)
    connection.try(&.send_packet(packet_bytes))
  end

  def send_chat_message(message : String)
    # Create a system chat message
    chat_packet = Clientbound::SystemChatMessage.new(
      TextComponent.new(message),
      false # Not an overlay message
    )
    send_packet(chat_packet)
  end

  def send_lockout_message
    send_chat_message("§c⚠ BOT LOCKOUT ACTIVE ⚠§r")
    send_chat_message("§7Bot is currently in control. Use §6/rosegold unlock§7 to take control.")
  end

  def send_unlock_message
    send_chat_message("§a✓ CLIENT CONTROL ENABLED§r")
    send_chat_message("§7You can now control the bot. Use §6/rosegold lock§7 to let bot take control.")
  end

  def disconnect(reason : String = "Disconnected")
    @socket.close unless @socket.closed?
    Log.info { "Client #{@username} disconnected: #{reason}" }
  end

  # Send essential packets that a client needs when entering PLAY state
  private def send_essential_play_packets
    bot = @proxy.bot
    return unless bot

    Log.info { "Sending essential PLAY packets to client #{@username}" }

    # 1. JoinGame - absolutely required as first PLAY packet
    send_join_game_packet

    # 2. Set default spawn position - defines where player spawns and compass points
    spawn_position = Vec3i.new(
      (bot.player.feet.x.round).to_i,
      (bot.player.feet.y.round).to_i,
      (bot.player.feet.z.round).to_i
    )
    spawn_packet = Clientbound::SetDefaultSpawnPosition.new(
      location: spawn_position,
      angle: bot.player.look.yaw
    )
    send_packet(spawn_packet)
    Log.info { "Sent default spawn position: #{spawn_position} angle: #{bot.player.look.yaw}°" }

    # 3. Set chunk cache center - defines center of chunk loading area
    player_chunk_x = (bot.player.feet.x / 16).floor.to_i
    player_chunk_z = (bot.player.feet.z / 16).floor.to_i
    center_chunk_packet = Clientbound::SetChunkCacheCenter.new(
      chunk_x: player_chunk_x,
      chunk_z: player_chunk_z
    )
    send_packet(center_chunk_packet)
    Log.info { "Sent chunk cache center: (#{player_chunk_x}, #{player_chunk_z})" }

    # 4. Player position - required so client knows where it is
    pos_packet = Clientbound::SynchronizePlayerPosition.new(
      x_raw: bot.player.feet.x,
      y_raw: bot.player.feet.y,
      z_raw: bot.player.feet.z,
      yaw_raw: bot.player.look.yaw,
      pitch_raw: bot.player.look.pitch,
      relative_flags: 0_u8, # Absolute positioning
      teleport_id: 1_u32
    )
    send_packet(pos_packet)
    Log.info { "Sent player position: #{bot.player.feet}" }

    # 5. Health update - important for client state
    health_packet = Clientbound::UpdateHealth.new(
      health: bot.player.health,
      food: bot.player.food,
      saturation: 5.0_f32 # Default food saturation
    )
    send_packet(health_packet)
    Log.info { "Sent health update: #{bot.player.health}/20" }

    # 6. Player abilities - spectator mode abilities
    # Spectators are invulnerable, can fly, and can move through blocks
    abilities_flags = 0_u8
    abilities_flags |= 0x01 # Invulnerable
    abilities_flags |= 0x02 # Flying
    abilities_flags |= 0x04 # Allow flying

    abilities_packet = Clientbound::PlayerAbilities.new(
      flags: abilities_flags,
      flying_speed: 0.05_f32,         # Default spectator flying speed
      field_of_view_modifier: 0.1_f32 # Default FOV modifier
    )
    send_packet(abilities_packet)
    Log.info { "Sent player abilities: flags=0x#{abilities_flags.to_s(16).upcase.rjust(2, '0')}, flying_speed=0.05, fov=0.1 (spectator mode)" }

    # 7. Ticking state - sets game tick rate and freeze status
    ticking_state_packet = Clientbound::TickingState.new(
      tick_rate: 20.0_f32, # Standard Minecraft tick rate
      is_frozen: false     # Normal game flow
    )
    send_packet(ticking_state_packet)
    Log.info { "Sent ticking state: tick_rate=20.0, frozen=false" }

    # 8. Add bot player to player list - makes bot visible in tab list
    bot_uuid = bot.player.uuid || UUID.random
    bot_name = bot.offline.try(&.[:username]) || "SpectateBot"
    player_info_packet = Clientbound::PlayerInfoUpdate.add_player(
      uuid: bot_uuid,
      name: bot_name,
      gamemode: 0, # Survival mode
      latency: 0,
      properties: [] of Clientbound::PlayerInfoUpdate::PlayerEntry::Property
    )
    send_packet(player_info_packet)
    Log.info { "Added bot player #{bot_name} (#{bot_uuid}) to player list" }

    # 9. Spawn bot as visible entity (VarInt compatible entity ID)
    bot_entity_id = (1000 + (bot_name.hash.abs % 10000)).to_u32
    Log.info { "Bot position: #{bot.player.feet} (Y=#{bot.player.feet.y} is #{bot.player.feet.y > 100 ? "HIGH" : "normal"})" }
    spawn_entity_packet = Clientbound::SpawnLivingEntity.new(
      entity_id: bot_entity_id,
      uuid: bot_uuid,
      entity_type: 149_u32, # Player entity type
      x: bot.player.feet.x,
      y: bot.player.feet.y,
      z: bot.player.feet.z,
      pitch: bot.player.look.pitch.to_f64,
      yaw: bot.player.look.yaw.to_f64,
      head_yaw: bot.player.look.yaw.to_f64,
      data: 0_u32,
      velocity_x: 0_i16,
      velocity_y: 0_i16,
      velocity_z: 0_i16
    )
    send_packet(spawn_entity_packet)
    Log.info { "Spawned bot entity with ID #{bot_entity_id} at #{bot.player.feet}" }
    # log packet contents
    packet_bytes = spawn_entity_packet.write
    Log.info { "SpawnLivingEntity contents: #{packet_bytes}" }

    # 10. Game event - signals client ready state and chunk waiting
    game_event_packet = Clientbound::GameEvent.start_waiting_for_chunks
    send_packet(game_event_packet)
    Log.info { "Sent game event: start waiting for level chunks" }

    # 11. Send chunks - essential for world rendering
    send_chunks

    # 12. Set camera to follow bot entity (spectator mode)
    set_camera_packet = Clientbound::SetCamera.new(bot_entity_id)
    send_packet(set_camera_packet)
    Log.info { "Set camera to follow bot entity #{bot_entity_id}" }

    Log.info { "Completed sending essential PLAY packets (JoinGame, SetDefaultSpawnPosition, SetChunkCacheCenter, SynchronizePlayerPosition, UpdateHealth, PlayerAbilities, TickingState, PlayerInfoUpdate, SpawnLivingEntity, GameEvent, Chunks, SetCamera) to client #{@username}" }
  end

  # Send a minimal JoinGame packet with basic values
  private def send_join_game_packet
    Log.info { "Sending minimal JoinGame packet to client #{@username}" }

    # Create a basic JoinGame packet with minimal required data
    # Note: dimension_type should be var_int, not u32
    join_game = Clientbound::JoinGame.new(
      entity_id: 1_i32, # Simple entity ID
      hardcore: false,
      dimension_names: ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end"], # Basic dimensions
      max_players: 20_u32,
      view_distance: 10_u32,      # Reduced view distance
      simulation_distance: 8_u32, # Reduced simulation distance
      reduced_debug_info: false,
      enable_respawn_screen: true,
      do_limited_crafting: false,
      dimension_type: 0_u32, # This needs to match the read method type
      dimension_name: "minecraft:overworld",
      hashed_seed: 0_i64,
      gamemode: 3_u8, # Spectator mode for spectating
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

    # Debug: show the actual packet bytes being sent
    packet_bytes = join_game.write
    Log.info { "JoinGame packet size: #{packet_bytes.size} bytes" }
    Log.info { "JoinGame packet data: #{packet_bytes[0, [32, packet_bytes.size].min].map { |b| "0x#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")}" }

    send_packet(join_game)
  end

  # Send available chunk data from the bot's loaded chunks
  private def send_available_chunks
    bot = @proxy.bot
    return unless bot

    player_chunk_x = (bot.player.feet.x / 16).floor.to_i
    player_chunk_z = (bot.player.feet.z / 16).floor.to_i

    Log.info { "Looking for chunks around player position (#{player_chunk_x}, #{player_chunk_z})" }

    # Try to send chunks around the player position from bot's loaded chunks
    chunks_sent = 0
    (-1..1).each do |dx|
      (-1..1).each do |dz|
        chunk_x = player_chunk_x + dx
        chunk_z = player_chunk_z + dz

        # Check if bot has this chunk loaded
        if chunk = bot.dimension.chunk_at?(chunk_x, chunk_z)
          Log.info { "Sending chunk (#{chunk_x}, #{chunk_z}) to client" }
          # We would need to create a ChunkData packet here, but that's complex
          # For now, let's just note that we found chunks
          chunks_sent += 1
        end
      end
    end

    if chunks_sent == 0
      Log.warn { "No chunks available to send to client - this may cause rendering issues" }
    else
      Log.info { "Found #{chunks_sent} chunks around player position" }
    end
  end

  # Send configuration packets including known packs and registry data
  private def send_configuration_packets
    Log.info { "Sending configuration packets to client #{@username}" }

    # Send update tags FIRST - these define blocks, items, etc. that may be referenced by other packets
    if bot_update_tags = get_bot_update_tags
      Log.info { "Sending #{bot_update_tags.tag_types.size} stored tag types from bot" }
      send_packet(bot_update_tags)
    else
      Log.info { "No stored update tags from bot, sending empty update tags" }
      empty_update_tags = Clientbound::UpdateTags.new
      send_packet(empty_update_tags)
    end

    # Send known packs SECOND - informs client about data packs before registry data
    if bot_known_packs = get_bot_known_packs
      Log.info { "Sending #{bot_known_packs.size} stored known packs from bot" }
      known_packs_packet = Clientbound::KnownPacks.new(bot_known_packs)
      send_packet(known_packs_packet)
    else
      Log.info { "No stored known packs from bot, sending empty known packs" }
      empty_known_packs = Clientbound::KnownPacks.new
      send_packet(empty_known_packs)
    end

    # Send registry data AFTER known packs - registry content may depend on data packs
    if bot_registries = get_bot_registries
      Log.info { "Sending #{bot_registries.size} stored registries from bot" }
      bot_registries.each do |registry_id, registry_data|
        send_packet(registry_data)
        Log.debug { "Sent stored registry: #{registry_id} with #{registry_data.entries.size} entries" }
      end
    else
      Log.info { "No stored registry data from bot, sending minimal registry data" }
      send_minimal_registry_data
    end

    # Send FinishConfiguration to transition to PLAY state
    Log.debug { "Sending FinishConfiguration to client #{@username}" }
    send_packet(Clientbound::FinishConfiguration.new)
  end

  # Get registry data from the bot's stored registries
  private def get_bot_registries : Hash(String, Clientbound::RegistryData)?
    bot = @proxy.bot
    return nil unless bot

    registries = bot.registries
    return nil if registries.empty?

    registries
  end

  # Get known packs from the bot's stored known packs
  private def get_bot_known_packs : Array(NamedTuple(namespace: String, id: String, version: String))?
    bot = @proxy.bot
    return nil unless bot

    known_packs = bot.known_packs
    return nil if known_packs.empty?

    known_packs
  end

  # Get update tags from the bot's stored tags
  private def get_bot_update_tags : Clientbound::UpdateTags?
    bot = @proxy.bot
    return nil unless bot

    bot.tags
  end

  # Send minimal registry data to prevent client registry errors
  private def send_minimal_registry_data
    Log.info { "Sending minimal registry data to client #{@username}" }

    # Send dimension_type registry with basic entries - this is critical for JoinGame
    send_dimension_type_registry

    # Send basic biome registry
    send_biome_registry

    # Send other required registries with single minimal entries
    minimal_registries = {
      "minecraft:damage_type"      => "minecraft:generic",
      "minecraft:banner_pattern"   => "minecraft:base",
      "minecraft:chat_type"        => "minecraft:chat",
      "minecraft:enchantment"      => "minecraft:protection",
      "minecraft:painting_variant" => "minecraft:kebab",
      "minecraft:trim_material"    => "minecraft:iron",
      "minecraft:trim_pattern"     => "minecraft:sentry",
      "minecraft:cat_variant"      => "minecraft:tabby",
      "minecraft:wolf_variant"     => "minecraft:pale",
      "minecraft:instrument"       => "minecraft:ponder_goat_horn",
      "minecraft:jukebox_song"     => "minecraft:13",
    }

    minimal_registries.each do |registry_id, entry_id|
      begin
        # Create registry with single entry (no NBT data)
        registry_packet = Clientbound::RegistryData.new(
          registry_id,
          [{id: entry_id, data: nil}] of Clientbound::RegistryData::RegistryEntry
        )
        send_packet(registry_packet)
        Log.debug { "Sent minimal registry: #{registry_id} with entry #{entry_id}" }
      rescue e
        Log.error { "Failed to send minimal registry #{registry_id}: #{e}" }
      end
    end

    Log.info { "Completed sending minimal registry data" }
  end

  # Send dimension_type registry with required entries
  private def send_dimension_type_registry
    # Create minimal but valid NBT data for dimension types
    # This is the bare minimum data structure that Minecraft expects
    overworld_nbt = create_minimal_dimension_nbt(
      has_skylight: true,
      has_ceiling: false,
      ambient_light: 0.0,
      fixed_time: nil,
      height: 384,
      min_y: -64,
      logical_height: 384
    )

    nether_nbt = create_minimal_dimension_nbt(
      has_skylight: false,
      has_ceiling: true,
      ambient_light: 0.1,
      fixed_time: 18000_i64,
      height: 256,
      min_y: 0,
      logical_height: 128
    )

    end_nbt = create_minimal_dimension_nbt(
      has_skylight: false,
      has_ceiling: false,
      ambient_light: 0.0,
      fixed_time: 6000_i64,
      height: 256,
      min_y: 0,
      logical_height: 256
    )

    # Dimension types required by JoinGame packet
    dimension_entries = [
      {id: "minecraft:overworld", data: overworld_nbt},
      {id: "minecraft:overworld_caves", data: overworld_nbt}, # Reuse overworld data
      {id: "minecraft:the_nether", data: nether_nbt},
      {id: "minecraft:the_end", data: end_nbt},
    ] of Clientbound::RegistryData::RegistryEntry

    registry_packet = Clientbound::RegistryData.new("minecraft:dimension_type", dimension_entries)

    # Debug: check the packet structure
    packet_bytes = registry_packet.write
    packet_id = packet_bytes[0]?
    Log.debug { "RegistryData packet ID: 0x#{packet_id.try(&.to_s(16).upcase.rjust(2, '0'))} (should be 0x05)" }
    Log.debug { "RegistryData packet size: #{packet_bytes.size} bytes" }

    send_packet(registry_packet)
    Log.debug { "Sent dimension_type registry with #{dimension_entries.size} entries containing NBT data" }
  end

  # Create minimal NBT data for dimension types
  private def create_minimal_dimension_nbt(has_skylight : Bool, has_ceiling : Bool, ambient_light : Float64, fixed_time : Int64?, height : Int32, min_y : Int32, logical_height : Int32) : Slice(UInt8)
    # Create a minimal NBT compound with required dimension type fields using proper NBT tag types
    nbt_tags = {
      "has_skylight"                    => Minecraft::NBT::ByteTag.new(has_skylight ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "has_ceiling"                     => Minecraft::NBT::ByteTag.new(has_ceiling ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "ambient_light"                   => Minecraft::NBT::FloatTag.new(ambient_light.to_f32).as(Minecraft::NBT::Tag),
      "height"                          => Minecraft::NBT::IntTag.new(height).as(Minecraft::NBT::Tag),
      "min_y"                           => Minecraft::NBT::IntTag.new(min_y).as(Minecraft::NBT::Tag),
      "logical_height"                  => Minecraft::NBT::IntTag.new(logical_height).as(Minecraft::NBT::Tag),
      "coordinate_scale"                => Minecraft::NBT::FloatTag.new(1.0_f32).as(Minecraft::NBT::Tag),
      "bed_works"                       => Minecraft::NBT::ByteTag.new((!has_ceiling) ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "respawn_anchor_works"            => Minecraft::NBT::ByteTag.new(has_ceiling ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "has_raids"                       => Minecraft::NBT::ByteTag.new((!has_ceiling) ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "ultrawarm"                       => Minecraft::NBT::ByteTag.new(has_ceiling ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "natural"                         => Minecraft::NBT::ByteTag.new(1_u8).as(Minecraft::NBT::Tag),
      "piglin_safe"                     => Minecraft::NBT::ByteTag.new(has_ceiling ? 1_u8 : 0_u8).as(Minecraft::NBT::Tag),
      "monster_spawn_light_level"       => Minecraft::NBT::IntTag.new(0).as(Minecraft::NBT::Tag),
      "monster_spawn_block_light_limit" => Minecraft::NBT::IntTag.new(0).as(Minecraft::NBT::Tag),
    }

    # Add fixed_time if specified
    if time = fixed_time
      nbt_tags = nbt_tags.merge({"fixed_time" => Minecraft::NBT::LongTag.new(time).as(Minecraft::NBT::Tag)})
    end

    nbt_compound = Minecraft::NBT::CompoundTag.new(nbt_tags)

    # Convert to NBT bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      nbt_compound.write_named(buffer, "")
    end.to_slice
  end

  # Send biome registry with basic entries
  private def send_biome_registry
    # Basic biomes that most worlds need
    biome_entries = [
      {id: "minecraft:plains", data: nil},
      {id: "minecraft:desert", data: nil},
      {id: "minecraft:forest", data: nil},
      {id: "minecraft:ocean", data: nil},
      {id: "minecraft:the_void", data: nil},
    ] of Clientbound::RegistryData::RegistryEntry

    registry_packet = Clientbound::RegistryData.new("minecraft:worldgen/biome", biome_entries)
    send_packet(registry_packet)
    Log.debug { "Sent worldgen/biome registry with #{biome_entries.size} entries" }
  end

  # Send all chunks stored on the bot to the spectate client
  private def send_chunks
    bot = @proxy.bot
    return unless bot

    chunks = bot.dimension.chunks
    Log.info { "Bot has #{chunks.size} chunks loaded" }

    if chunks.empty?
      Log.info { "No chunks loaded from bot, generating minimal chunks around player position" }
      send_minimal_chunks_around_player
    else
      Log.info { "Sending #{chunks.size} chunks to spectate client #{@username}" }

      chunks.each_with_index do |(chunk_pos, chunk), index|
        begin
          # Create ChunkData packet from the stored chunk
          chunk_packet = Clientbound::ChunkData.new(chunk)
          send_packet(chunk_packet)

          Log.debug { "Sent chunk #{index + 1}/#{chunks.size}: (#{chunk_pos[0]}, #{chunk_pos[1]})" }

          # Small delay between chunks to avoid overwhelming the client
          sleep 0.01.seconds if index % 5 == 0
        rescue e
          Log.error { "Failed to send chunk at #{chunk_pos}: #{e}" }
        end
      end

      Log.info { "Completed sending #{chunks.size} chunks to spectate client #{@username}" }
    end
  end

  # Send minimal empty chunks around the player position to prevent terrain loading freeze
  private def send_minimal_chunks_around_player
    bot = @proxy.bot
    return unless bot

    player_chunk_x = (bot.player.feet.x / 16).floor.to_i
    player_chunk_z = (bot.player.feet.z / 16).floor.to_i

    Log.info { "Generating minimal chunks around player position (#{player_chunk_x}, #{player_chunk_z})" }

    # Send a 3x3 grid of chunks around the player
    chunk_count = 0
    (-1..1).each do |dx|
      (-1..1).each do |dz|
        chunk_x = player_chunk_x + dx
        chunk_z = player_chunk_z + dz

        begin
          # Create minimal empty chunk data
          empty_chunk_packet = create_empty_chunk_packet(chunk_x, chunk_z)
          send_packet(empty_chunk_packet)

          chunk_count += 1
          Log.debug { "Sent empty chunk #{chunk_count}/9: (#{chunk_x}, #{chunk_z})" }
        rescue e
          Log.error { "Failed to send empty chunk at (#{chunk_x}, #{chunk_z}): #{e}" }
        end
      end
    end

    Log.info { "Completed sending #{chunk_count} minimal chunks to spectate client #{@username}" }
  end

  # Create an empty ChunkData packet for the specified coordinates
  private def create_empty_chunk_packet(chunk_x : Int32, chunk_z : Int32) : Clientbound::ChunkData
    # Create minimal chunk data - all air blocks
    # This is a simplified approach that creates the minimum data needed

    # For MC 1.21, we need sections from Y -64 to Y 320 (384 blocks = 24 sections)
    # Each section is 16x16x16 blocks
    empty_sections = Bytes.new(0) # Completely empty - no block data

    # Create minimal heightmaps (all zeros for flat terrain at bottom)
    empty_heightmaps = [Heightmap.new(1_u32, [] of Int64)] # WORLD_SURFACE type

    # Create empty light data
    empty_light_data = Bytes.new(0)

    # Create the ChunkData packet with minimal data
    Clientbound::ChunkData.new(
      chunk_x,
      chunk_z,
      empty_heightmaps,
      empty_sections,
      [] of Chunk::BlockEntity,
      empty_light_data
    )
  end

  # Determine if a packet needs special handling by the proxy
  # Only these packets should be parsed - all others are forwarded raw
  private def should_handle_packet_specially?(packet_id : UInt8?, protocol_state : ProtocolState) : Bool
    return false unless packet_id

    case protocol_state
    when ProtocolState::HANDSHAKING
      packet_id == 0x00 # Handshake packet
    when ProtocolState::STATUS
      packet_id == 0x00 || packet_id == 0x01 # StatusRequest, StatusPing
    when ProtocolState::LOGIN
      packet_id == 0x00 || packet_id == 0x03 # LoginStart, LoginAcknowledged
    when ProtocolState::CONFIGURATION
      packet_id == 0x03 # FinishConfiguration
    when ProtocolState::PLAY
      packet_id == 0x08 # ChatMessage (for /rosegold commands)
    else
      false
    end
  end
end
