require "socket"
require "./events/*"
require "./packets/*"
require "./world/*"
require "../minecraft/nbt"
require "../minecraft/io"

# Forward declaration to avoid circular dependency
class Rosegold::Client; end

# A spectate server that allows Minecraft clients to connect and observe the bot's gameplay in real-time.
# Provides a "headless with headful feel" experience by forwarding packets, synchronizing world state,
# and replicating the bot's perspective including inventory, position, chunk data, and player interactions.
#
# **Note:** This is in early development and not perfect. It provides essential functionality for debugging
# complex headless bots by allowing visual inspection of their behavior, but may have visual glitches,
# missing features, or synchronization issues.
#
# ## Usage Example
#
# ```
# # Initialize and start the spectate server
# spectate_server = Rosegold::SpectateServer.new("127.0.0.1", 25566)
# spectate_server.start
#
# # Create and attach a Rosegold client to the spectate server
# client = Rosegold::Client.new("play.example.com")
# spectate_server.attach_client(client)
#
# bot = Rosegold::Bot.new(client)
# bot.join_game
#
# # Now Minecraft clients can connect to localhost:25566 to spectate the bot
# # The spectator will see everything the bot sees: world, inventory, entities, etc.
#
# # You would do bot logic after joining the game, e.g.:
# bot.move_to 10, 10
#
# # To stop the spectate server prematurely:
# spectate_server.stop
# ```
class Rosegold::SpectateServer
  # Configuration constants
  DEFAULT_SPECTATOR_ENTITY_ID = 0x7fffffff
  DEFAULT_RENDER_DISTANCE     =          3
  DEFAULT_VIEW_DISTANCE       =      3_u32
  DEFAULT_SIMULATION_DISTANCE =      3_u32
  KEEP_ALIVE_INTERVAL         = 20.seconds
  INVENTORY_POLL_INTERVAL     = 1.second
  BOT_MONITOR_INTERVAL        = 50.milliseconds

  # Packet IDs for raw forwarding
  FORWARDED_PACKETS = {
    0x72_u8 => "SystemChatMessage",
    0x11_u8 => "CloseWindow",
    0x34_u8 => "OpenWindow",
    0x08_u8 => "BlockChange",
    0x4D_u8 => "MultiBlockChange",
    0x01_u8 => "SpawnEntity",
    0x1F_u8 => "EntityPositionSync",
    0x2E_u8 => "move_entity_pos",
    0x31_u8 => "EntityRotation",
    0x2F_u8 => "move_entity_pos_rot",
    0x5F_u8 => "EntityEquipment",
    0x5E_u8 => "set_entity_motion",
    0x5C_u8 => "set_entity_data",
    0x46_u8 => "remove_entities",
    0x7C_u8 => "update_attributes",
    0x3F_u8 => "PlayerInfoUpdate",
    0x3E_u8 => "PlayerInfoRemove",
    0x6E_u8 => "sound",
    0x05_u8 => "block_destruction",
    0x12_u8 => "SetContainerContent",
    0x14_u8 => "SetSlot",
    0x61_u8 => "UpdateHealth",
    0x7D_u8 => "EntityEffect",
    0x47_u8 => "RemoveEntityEffect",
  }
  Log = ::Log.for self

  property host : String
  property port : Int32
  property client : Rosegold::Client?
  property server : TCPServer?
  property connections = Array(SpectateConnection).new

  # Creates a new SpectateServer.
  #
  # - `host`: IP address to bind to (default: "127.0.0.1")
  # - `port`: Port to listen on (default: 25566)
  def initialize(@host : String = "127.0.0.1", @port : Int32 = 25566)
  end

  # Starts the spectate server and begins listening for connections.
  # Spawns a fiber to handle connections asynchronously.
  # Multiple spectators can connect simultaneously.
  def start
    @server = TCPServer.new(host, port)
    Log.info { "SpectateServer listening on #{host}:#{port}" }

    spawn do
      while server = @server
        begin
          client_socket = server.accept
          Log.info { "New spectator connection from #{client_socket.remote_address}" }

          connection = SpectateConnection.new(client_socket, self)
          @connections << connection

          spawn do
            connection.handle_client
          rescue e
            Log.error { "Spectator connection error: #{e}" }
          ensure
            @connections.delete(connection)
            client_socket.close
          end
        rescue e : IO::Error
          Log.debug { "Server accept error: #{e}" }
          break if server.closed?
        end
      end
    end
  end

  def stop
    @server.try &.close
    @connections.each(&.close)
    @connections.clear
  end

  # Attaches a Rosegold client so spectators can observe its gameplay.
  # Only one client can be attached at a time.
  def attach_client(client : Rosegold::Client)
    @client = client
  end

  def detach_client
    @client = nil
  end
end

# Represents a single spectator client connection
class Rosegold::SpectateConnection
  Log = ::Log.for self

  property socket : Minecraft::IO::Wrap
  property spectate_server : SpectateServer
  property protocol_state : ProtocolState
  property client : Rosegold::Client?
  property username : String = "SpectatorBot"
  property uuid : UUID = UUID.random
  property keep_alive_id : Int64 = 0_i64
  property loaded_chunks : Set(Tuple(Int32, Int32)) = Set(Tuple(Int32, Int32)).new
  property teleport_id : UInt32 = 1_u32
  property? connected : Bool = true
  property last_digging_block : Vec3i? = nil
  property last_dig_progress : Float32 = 0.0_f32
  property last_swing_countdown : Int8 = 0_i8
  @packet_send_mutex = Mutex.new

  def initialize(raw_socket : TCPSocket, @spectate_server : SpectateServer)
    @socket = Minecraft::IO::Wrap.new(raw_socket)
    @protocol_state = ProtocolState::HANDSHAKING
    @client = @spectate_server.client
  end

  private def protocol_version : UInt32
    @client.try(&.protocol_version) || 772_u32
  end

  def handle_client
    Log.debug { "Starting spectator client handler" }

    loop do
      break unless @connected
      # Read packet manually and use decode_serverbound_packet
      packet_data = read_raw_packet
      packet = Connection.decode_serverbound_packet(packet_data, @protocol_state, protocol_version)
      Log.trace { "Received packet: #{packet.class.name} in state: #{@protocol_state}" }

      case packet
      when Rosegold::Serverbound::Handshake
        handle_handshake(packet)
      when Rosegold::Serverbound::StatusRequest
        handle_status_request
      when Rosegold::Serverbound::StatusPing
        handle_status_ping(packet)
      when Rosegold::Serverbound::LoginStart
        handle_login_start(packet)
      when Rosegold::Serverbound::LoginAcknowledged
        handle_login_acknowledged
      when Rosegold::Serverbound::ClientInformation
        handle_client_information
      when Rosegold::Serverbound::FinishConfiguration
        handle_finish_configuration
      when Rosegold::Serverbound::KeepAlive
        handle_keep_alive(packet)
      else
        Log.trace { "Unhandled packet: #{packet.class.name}" }
      end
    end
  rescue e : IO::Error
    close
    Log.trace { "Spectator client disconnected: #{e}" }
  rescue e
    close
    Log.error { "Spectator connection error: #{e}" }
    e.backtrace?.try { |backtrace| Log.error { backtrace.join("\n") } }
  end

  private def read_raw_packet : Bytes
    # Simple packet reading without compression for now
    packet_bytes = Bytes.new(socket.read_var_int)
    socket.read_fully(packet_bytes)
    packet_bytes
  rescue e : IO::Error
    raise e
  end

  private def handle_handshake(packet : Rosegold::Serverbound::Handshake)
    Log.debug { "Handshake: protocol=#{packet.protocol_version}, next_state=#{packet.next_state}" }

    @connected = true

    case packet.next_state
    when 1 # Status
      @protocol_state = ProtocolState::STATUS
    when 2 # Login
      @protocol_state = ProtocolState::LOGIN
    end
  end

  private def handle_login_start(packet : Rosegold::Serverbound::LoginStart)
    @username = packet.username
    @uuid = UUID.random # For offline mode

    Log.info { "Login start for #{@username}" }

    # Check if bot is connected before proceeding
    unless client_connected?
      Log.warn { "Client #{@username} attempting to login but no bot is connected" }
      send_disconnect("No bot available for spectating")
      return
    end

    # Send Login Success (offline mode)
    send_login_success
    # Don't transition state yet - wait for LoginAcknowledged
  end

  private def handle_login_acknowledged
    Log.debug { "Received Login Acknowledged, transitioning to configuration" }
    @protocol_state = ProtocolState::CONFIGURATION
  end

  private def handle_client_information
    Log.debug { "Received client information" }

    send_configuration_packets
  end

  private def handle_finish_configuration
    Log.debug { "Configuration acknowledged, switching to play" }

    @protocol_state = ProtocolState::PLAY

    spawn do
      sleep 0.1.seconds
      send_play_packets
    end
  end

  private def handle_keep_alive(packet : Rosegold::Serverbound::KeepAlive)
    Log.trace { "Received keep-alive response: #{packet.keep_alive_id}" }
    # Client is responding to our keep-alive, connection is good
  end

  private def handle_status_request
    Log.debug { "Received status request, sending server status" }

    # Determine player count based on bot connection
    online_players = client_connected? ? 1 : 0
    max_players = 1

    # Create status response JSON
    status_json = {
      "version" => {
        "name"     => "1.21.8",
        "protocol" => protocol_version,
      },
      "players" => {
        "max"    => max_players,
        "online" => online_players,
        "sample" => [] of Hash(String, String),
      },
      "description" => {
        "text" => "Rosegold SpectateServer - #{client_connected? ? "Bot Connected" : "Waiting for Bot"}",
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

    # Close connection after ping/pong exchange
    spawn do
      sleep 0.1.seconds
      close
    end
  end

  private def send_login_success
    packet = Rosegold::Clientbound::LoginSuccess.new(@uuid, @username, [] of Rosegold::Clientbound::LoginSuccess::Property)
    send_packet(packet)
  end

  private def send_disconnect(reason : String)
    # Send disconnect packet based on current protocol state
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
      # For HANDSHAKING state or unknown states, just close connection
      close
      return
    end

    # Close the connection after sending disconnect
    spawn do
      sleep 0.1.seconds
      close
    end
  end

  private def send_configuration_packets
    Log.info { "Sending configuration packets to client #{@username}" }

    # Send update tags FIRST - these define blocks, items, etc. that may be referenced by other packets
    if bot_update_tags = get_bot_update_tags
      Log.info { "Sending #{bot_update_tags.tag_types.size} stored tag types from bot" }
      send_packet(bot_update_tags)
    else
      Log.info { "No stored update tags from bot, sending empty update tags" }
      empty_update_tags = Rosegold::Clientbound::UpdateTags.new
      send_packet(empty_update_tags)
    end

    # Send known packs SECOND - informs client about data packs before registry data
    if bot_known_packs = get_bot_known_packs
      Log.info { "Sending #{bot_known_packs.size} stored known packs from bot" }
      known_packs_packet = Rosegold::Clientbound::KnownPacks.new(bot_known_packs)
      send_packet(known_packs_packet)
    else
      Log.info { "No stored known packs from bot, sending empty known packs" }
      empty_known_packs = Rosegold::Clientbound::KnownPacks.new
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
    send_packet(Rosegold::Clientbound::FinishConfiguration.new)
  end

  # Get registry data from the bot's stored registries
  private def get_bot_registries : Hash(String, Rosegold::Clientbound::RegistryData)?
    bot = @client
    return nil unless bot

    registries = bot.registries
    return nil if registries.empty?

    registries
  end

  # Get known packs from the bot's stored known packs
  private def get_bot_known_packs : Array(NamedTuple(namespace: String, id: String, version: String))?
    bot = @client
    return nil unless bot

    known_packs = bot.known_packs
    return nil if known_packs.empty?

    known_packs
  end

  # Get update tags from the bot's stored tags
  private def get_bot_update_tags : Rosegold::Clientbound::UpdateTags?
    bot = @client
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
        registry_packet = Rosegold::Clientbound::RegistryData.new(
          registry_id,
          [{id: entry_id, data: nil}] of Rosegold::Clientbound::RegistryData::RegistryEntry
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
    # Create dimension_type registry with overworld entry
    entries = [{
      id:   "minecraft:overworld",
      data: nil.as(Slice(UInt8) | Nil),
    }]

    registry_packet = Rosegold::Clientbound::RegistryData.new(
      "minecraft:dimension_type",
      entries
    )

    Log.debug { "Sending minimal dimension_type registry" }
    send_packet(registry_packet)
  end

  # Send biome registry with required entries
  private def send_biome_registry
    # Create biome registry with basic entries
    entries = [{
      id:   "minecraft:plains",
      data: nil.as(Slice(UInt8) | Nil),
    }]

    registry_packet = Rosegold::Clientbound::RegistryData.new(
      "minecraft:worldgen/biome",
      entries
    )

    Log.debug { "Sending minimal biome registry" }
    send_packet(registry_packet)
  end

  private def send_start_waiting_for_chunks
    # This is the critical packet that tells the client to start processing chunks
    # Without this, the client hangs on "Loading terrain..." indefinitely
    packet = Rosegold::Clientbound::GameEvent.start_waiting_for_chunks
    send_packet(packet)
    Log.debug { "Sent start waiting for chunks game event" }
  end

  private def send_play_packets
    return unless bot = @client

    send_join_game
    send_set_ticking_state(false)
    send_player_abilities
    send_player_position
    start_inventory_polling
    send_hotbar_selection(bot.player.hotbar_selection)
    send_start_waiting_for_chunks
    send_chunks
    send_existing_players
    send_existing_entities
    send_existing_entity_effects
    start_bot_monitoring
    setup_position_event_listener
    setup_raw_packet_relay
    start_keep_alive_sender
  end

  private def send_join_game
    bot = @client
    return unless bot

    packet = Rosegold::Clientbound::Login.new(
      entity_id: SpectateServer::DEFAULT_SPECTATOR_ENTITY_ID, # Use a default entity ID
      hardcore: false,
      dimension_names: ["minecraft:overworld"],
      max_players: 20_u32,
      view_distance: SpectateServer::DEFAULT_VIEW_DISTANCE,
      simulation_distance: SpectateServer::DEFAULT_SIMULATION_DISTANCE,
      reduced_debug_info: false,
      enable_respawn_screen: true,
      do_limited_crafting: false,
      dimension_type: 0_u32, # Default dimension type
      dimension_name: "minecraft:overworld",
      hashed_seed: 0_i64,
      gamemode: 0_u8, # Survival
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

  private def send_set_ticking_state(enabled : Bool)
    # When disabled, freeze the client (tick_rate doesn't matter when frozen)
    # When enabled, use normal tick rate of 20 TPS
    tick_rate = enabled ? 20.0_f32 : 0.0_f32
    is_frozen = !enabled
    packet = Rosegold::Clientbound::TickingState.new(tick_rate, is_frozen)
    send_packet(packet)
  end

  private def send_player_abilities
    # Flags: 0x02 = flying allowed (spectators can fly)
    packet = Rosegold::Clientbound::PlayerAbilities.new(
      0x02_u8,  # Flying allowed
      0.05_f32, # Flying speed
      0.1_f32   # Field of view modifier
    )
    send_packet(packet)
  end

  private def send_player_position
    return unless bot = @client

    packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
      bot.player.feet.x,
      bot.player.feet.y,
      bot.player.feet.z,
      bot.player.look.yaw,
      bot.player.look.pitch,
      0x00_u8, # No relative flags
      1_u32    # Teleport ID
    )

    send_packet(packet)
  end

  private def send_chunks
    return unless bot = @client

    # Send a simple chunk at the player's location
    player_chunk_x = (bot.player.feet.x / 16).floor.to_i32
    player_chunk_z = (bot.player.feet.z / 16).floor.to_i32

    # Set Center Chunk
    packet = Rosegold::Clientbound::SetChunkCacheCenter.new(player_chunk_x, player_chunk_z)
    send_packet(packet)

    # Send chunks from bot's dimension if available
    view_distance = 3
    (-view_distance..view_distance).each do |delta_x|
      (-view_distance..view_distance).each do |delta_z|
        chunk_x = player_chunk_x + delta_x
        chunk_z = player_chunk_z + delta_z

        if send_chunk_data(chunk_x, chunk_z)
          @loaded_chunks.add({chunk_x, chunk_z})
        end
      end
    end
  end

  private def start_bot_monitoring
    return unless bot = @client

    spawn do
      monitor_state = initialize_monitor_state(bot)

      loop do
        break unless @connected
        break unless bot.connected?
        sleep SpectateServer::BOT_MONITOR_INTERVAL

        update_monitor_state(monitor_state, bot)
        check_and_send_updates(monitor_state, bot)

        # Track block breaking progress and arm swinging
        track_block_breaking_progress(bot)
        track_arm_swinging(bot)
      end
    rescue e
      Log.error { "Bot monitoring error: #{e}" }
      Log.error exception: e
    end
  end

  private def initialize_monitor_state(bot)
    {
      "last_hotbar_selection" => bot.player.hotbar_selection,
      "last_chunk_pos"        => {(bot.player.feet.x / 16).floor.to_i32, (bot.player.feet.z / 16).floor.to_i32},
    }
  end

  private def update_monitor_state(monitor_state, bot)
    monitor_state["current_hotbar_selection"] = bot.player.hotbar_selection
    monitor_state["current_chunk_pos"] = {(bot.player.feet.x / 16).floor.to_i32, (bot.player.feet.z / 16).floor.to_i32}
  end

  private def check_and_send_updates(monitor_state, bot)
    check_hotbar_updates(monitor_state)
    check_chunk_updates(monitor_state)
  end

  private def check_hotbar_updates(monitor_state)
    current_hotbar_selection = monitor_state["current_hotbar_selection"].as(UInt32)

    if current_hotbar_selection != monitor_state["last_hotbar_selection"]
      send_hotbar_selection(current_hotbar_selection)
      monitor_state["last_hotbar_selection"] = current_hotbar_selection
    end
  end

  private def check_chunk_updates(monitor_state)
    current_chunk_pos = monitor_state["current_chunk_pos"].as(Tuple(Int32, Int32))

    if current_chunk_pos != monitor_state["last_chunk_pos"]
      update_chunks(current_chunk_pos)
      monitor_state["last_chunk_pos"] = current_chunk_pos
    end
  end

  private def send_player_position_update(position : Vec3d, look : Look)
    # Increment teleport ID for each position update
    @teleport_id = (@teleport_id + 1) % 999999999_u32 # Keep it reasonable but allow wrapping

    packet = Rosegold::Clientbound::SynchronizePlayerPosition.new(
      position.x,
      position.y,
      position.z,
      look.yaw,
      look.pitch,
      0x00_u8,     # No relative flags
      @teleport_id # Unique teleport ID
    )

    send_packet(packet)
  end

  private def send_hotbar_selection(hotbar_nr : UInt32)
    packet = Rosegold::Clientbound::HeldItemChange.new(hotbar_nr)
    send_packet(packet)
  end

  private def send_inventory_content
    return unless bot = @client

    # Get current inventory state
    inventory = bot.inventory_menu
    slots = [] of WindowSlot

    # Copy all slots from the current inventory state
    (0...inventory.slots.size).each do |i|
      slot = inventory.slots[i]
      slots << WindowSlot.new(i, slot)
    end

    # Create cursor slot
    cursor_slot = WindowSlot.new(-1, inventory.cursor)

    # Send SetContainerContent packet for player inventory (window_id = 0)
    # Use a safe state_id to avoid overflow
    safe_state_id = (inventory.state_id % UInt32::MAX).to_u32
    packet = Rosegold::Clientbound::SetContainerContent.new(
      window_id: 0_u32, # Player inventory
      state_id: safe_state_id,
      slots: slots,
      cursor: cursor_slot
    )
    send_packet(packet)
  end

  private def track_block_breaking_progress(bot : Rosegold::Client)
    # Access the bot's interactions to get digging state
    interactions = bot.interactions
    current_digging_block = interactions.@digging_block
    current_dig_progress = interactions.@block_damage_progress

    # Get current digging block position (if any)
    current_block_pos = if current_digging_block
                          current_digging_block.block
                        else
                          nil
                        end

    # Check if we started digging a new block
    if current_block_pos != @last_digging_block
      # Clear previous block's animation if there was one
      if previous_block = @last_digging_block
        send_block_destroy_stage(bot.player.entity_id, previous_block, 255_u8) # 255 = clear animation
        Log.debug { "Cleared block destroy animation at #{previous_block}" }
      end

      @last_digging_block = current_block_pos
      @last_dig_progress = 0.0_f32

      # Start animation for new block
      if current_block_pos
        send_block_destroy_stage(bot.player.entity_id, current_block_pos, 0_u8)
        Log.debug { "Started block destroy animation at #{current_block_pos}" }
      end
    end

    # Update progress if we're digging the same block
    if current_block_pos && current_dig_progress != @last_dig_progress
      # Convert progress (0.0 to 1.0) to destroy stage (0 to 9)
      destroy_stage = (current_dig_progress * 9.0).clamp(0.0, 9.0).to_u8

      send_block_destroy_stage(bot.player.entity_id, current_block_pos, destroy_stage)
      @last_dig_progress = current_dig_progress.to_f32
      Log.debug { "Updated block destroy progress: #{current_dig_progress.round(2)} -> stage #{destroy_stage}" }
    end

    # Clear animation if digging stopped
    if current_block_pos.nil? && @last_digging_block
      if previous_block = @last_digging_block
        send_block_destroy_stage(bot.player.entity_id, previous_block, 255_u8)
        Log.debug { "Stopped digging, cleared animation at #{previous_block}" }
      end
      @last_digging_block = nil
      @last_dig_progress = 0.0_f32
    end
  end

  private def send_block_destroy_stage(entity_id, location : Vec3i, destroy_stage : UInt8)
    packet = Rosegold::Clientbound::SetBlockDestroyStage.new(entity_id.to_i32, location, destroy_stage)
    send_packet(packet)
  end

  private def track_arm_swinging(bot : Rosegold::Client)
    # Access the bot's interactions to get swing countdown
    interactions = bot.interactions
    current_swing_countdown = interactions.@dig_hand_swing_countdown
    current_digging = interactions.digging?

    # Check if swing countdown reset from 1 to 6 (triggers a swing) AND we're digging
    if current_swing_countdown == 6 && @last_swing_countdown == 1 && current_digging
      # Bot just swung its arm - send animation to spectator
      send_entity_animation(bot.player.entity_id, Rosegold::Clientbound::EntityAnimation::Animation::SwingMainArm)
    end

    @last_swing_countdown = current_swing_countdown.to_i8
  end

  private def send_entity_animation(entity_id, animation : Rosegold::Clientbound::EntityAnimation::Animation)
    # Use the spectator client's entity ID from the login packet, not the bot's entity ID
    spectator_entity_id = SpectateServer::DEFAULT_SPECTATOR_ENTITY_ID
    packet = Rosegold::Clientbound::EntityAnimation.new(spectator_entity_id, animation)
    send_packet(packet)
  end

  private def update_chunks(current_chunk_pos : Tuple(Int32, Int32))
    chunk_x, chunk_z = current_chunk_pos

    # Set new chunk cache center
    center_packet = Rosegold::Clientbound::SetChunkCacheCenter.new(chunk_x, chunk_z)
    send_packet(center_packet)

    # Define render distance
    render_distance = SpectateServer::DEFAULT_RENDER_DISTANCE

    # Find chunks that are now too far away and should be unloaded
    chunks_to_unload = @loaded_chunks.select do |loaded_chunk_x, loaded_chunk_z|
      distance_x = (loaded_chunk_x - chunk_x).abs
      distance_z = (loaded_chunk_z - chunk_z).abs
      distance_x > render_distance || distance_z > render_distance
    end

    # Unload distant chunks
    chunks_to_unload.each do |old_chunk_x, old_chunk_z|
      unload_packet = Rosegold::Clientbound::UnloadChunk.new(old_chunk_x, old_chunk_z)
      send_packet(unload_packet)
      @loaded_chunks.delete({old_chunk_x, old_chunk_z})
    end

    # Load new chunks that are now within render distance
    chunks_to_load = [] of Tuple(Int32, Int32)

    (-render_distance..render_distance).each do |delta_x|
      (-render_distance..render_distance).each do |delta_z|
        new_chunk_x = chunk_x + delta_x
        new_chunk_z = chunk_z + delta_z
        chunk_pos = {new_chunk_x, new_chunk_z}

        # Skip if chunk is already loaded
        next if @loaded_chunks.includes?(chunk_pos)

        # Check if chunk is within circular render distance
        distance_sq = delta_x * delta_x + delta_z * delta_z
        next if distance_sq > render_distance * render_distance

        chunks_to_load << chunk_pos
      end
    end

    # Send chunk data for newly loaded chunks
    successfully_loaded = 0
    chunks_to_load.each do |load_chunk_x, load_chunk_z|
      if send_chunk_data(load_chunk_x, load_chunk_z)
        @loaded_chunks.add({load_chunk_x, load_chunk_z})
        successfully_loaded += 1
      end
    end
  end

  private def send_chunk_data(chunk_x : Int32, chunk_z : Int32) : Bool
    return false unless bot = @client

    # Get chunk from bot's current dimension
    chunk = bot.dimension.chunk_at?(chunk_x, chunk_z)

    if chunk
      # Send the actual chunk data
      chunk_packet = Rosegold::Clientbound::ChunkData.new(chunk)
      send_packet(chunk_packet)
      true
    else
      Log.warn { "Chunk (#{chunk_x}, #{chunk_z}) not available in bot's dimension. Bot has #{bot.dimension.chunks.size} chunks loaded." }

      # Show what chunks the bot actually has
      if bot.dimension.chunks.size > 0
        sample_chunks = bot.dimension.chunks.keys.first(5)
        Log.debug { "Sample chunks bot has: #{sample_chunks}" }
      end
      false
    end
  end

  private def send_existing_entities
    return unless bot = @client

    # Send SpawnEntity packets for all entities currently tracked by the bot
    entity_count = 0
    bot.dimension.entities.each do |entity_id, entity|
      # Create SpawnEntity packet for this entity
      spawn_packet = Rosegold::Clientbound::SpawnEntity.new(
        entity_id: entity_id.to_u32,
        uuid: entity.uuid,
        entity_type: entity.entity_type,
        x: entity.position.x,
        y: entity.position.y,
        z: entity.position.z,
        pitch: entity.pitch.to_f64,
        yaw: entity.yaw.to_f64,
        head_yaw: entity.head_yaw.to_f64,
        data: 0_u32, # Default data
        velocity_x: entity.velocity.x.to_i16,
        velocity_y: entity.velocity.y.to_i16,
        velocity_z: entity.velocity.z.to_i16
      )

      send_packet(spawn_packet)
      entity_count += 1
    end

    Log.info { "Sent #{entity_count} existing entities to spectator #{@username}" }
  end

  private def send_existing_entity_effects
    return unless bot = @client

    effect_count = 0

    # Send player effects only - these are the ones that impact the player directly
    bot.player.effects.each do |effect|
      # TODO: decrease to debug when done
      Log.info { "Sending existing effect #{effect.id} (amplifier #{effect.amplifier}, duration #{effect.duration}) to spectator #{@username}" }
      effect_packet = Rosegold::Clientbound::EntityEffect.new(
        bot.player.entity_id,
        effect.id.to_u32,
        effect.amplifier.to_u8,
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

    # Send PlayerInfoUpdate packets for all players currently tracked by the bot
    if bot.player_list.size > 0
      # Group players by what info needs to be sent and create packets accordingly
      all_players = bot.player_list.values.compact_map do |entry|
        next unless entry.name # Skip incomplete entries

        # Convert PlayerList::Property to PlayerInfoUpdate::PlayerEntry::Property
        properties = entry.properties.map do |prop|
          Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry::Property.new(
            prop.name, prop.value, prop.signature
          )
        end

        # Create PlayerEntry for the PlayerInfoUpdate packet
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
        # Send comprehensive PlayerInfoUpdate with all flags
        actions = Rosegold::Clientbound::PlayerInfoUpdate::ADD_PLAYER |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_GAMEMODE |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LISTED |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY |
                  Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_DISPLAY_NAME

        player_info_packet = Rosegold::Clientbound::PlayerInfoUpdate.new(actions, all_players)
        send_packet(player_info_packet)

        Log.info { "Sent info for #{all_players.size} existing players to spectator #{@username}" }
      else
        Log.info { "No complete player entries to send (spectator is the bot player)" }
      end
    else
      Log.info { "No additional players to spawn (spectator is the bot player)" }
    end
  end

  def send_packet(packet : Rosegold::Clientbound::Packet)
    return unless @connected
    Log.trace { "SEND #{packet}" }

    @packet_send_mutex.synchronize do
      return unless @connected
      data = packet.write
      socket.write(data.size)
      socket.write(data)
      socket.flush
    end
  rescue ex : IO::Error
    Log.debug { "Failed to send packet: #{ex}" }
  rescue ex
    Log.error { "Packet send error: #{ex}" }
  end

  private def start_keep_alive_sender
    spawn do
      loop do
        sleep SpectateServer::KEEP_ALIVE_INTERVAL
        break unless @connected
        @keep_alive_id = Time.utc.to_unix_ms
        keep_alive_packet = Rosegold::Clientbound::KeepAlive.new(@keep_alive_id)
        send_packet(keep_alive_packet)
      end
    rescue ex : IO::Error
      Log.debug { "Keep-alive connection closed: #{ex}" }
    rescue ex
      Log.error { "Keep-alive error: #{ex}" }
    end
  end

  private def start_inventory_polling
    spawn do
      loop do
        send_inventory_content
        sleep SpectateServer::INVENTORY_POLL_INTERVAL
        break unless @connected
        break unless bot = @client
        break unless bot.connected?
      end
    rescue ex
      Log.debug { "Inventory polling error: #{ex}" }
    end
  end

  private def setup_raw_packet_relay
    return unless bot = @client

    # Listen for raw packets and forward specific types verbatim
    bot.on(Rosegold::Event::RawPacket) do |event|
      raw_bytes = event.bytes
      next unless raw_bytes.size > 0

      if packet_name = SpectateServer::FORWARDED_PACKETS[raw_bytes[0]]?
        # Create RawPacket to forward
        relay_packet = Rosegold::Clientbound::RawPacket.new(raw_bytes)

        # Send only to this specific connection (not all connections)
        if @connected
          begin
            send_packet(relay_packet)
          rescue ex : IO::Error
            Log.debug { "Failed to relay #{packet_name}: connection closed" }
          rescue ex
            Log.error { "Failed to relay #{packet_name}: #{ex}" }
          end
        end
      end
    end
  end

  private def setup_position_event_listener
    return unless bot = @client

    # Listen for position update events and send position updates immediately
    bot.on(Rosegold::Event::PlayerPositionUpdate) do |event|
      next unless @connected
      send_player_position_update(event.position, event.look)
    end
  end

  def close
    @connected = false
    @socket.close
  rescue
    # Socket already closed
  end

  private def client_connected?
    @spectate_server.client.try &.connected? || false
  end
end
