require "socket"
require "../events/*"
require "../packets/*"
require "../world/*"
require "../../minecraft/nbt"
require "../../minecraft/io"

# Forward declaration to avoid circular dependency
class Rosegold::Client; end

class Rosegold::Spectate::Server
  DEFAULT_SPECTATOR_ENTITY_ID = 0x7fffffff
  LOOK_UPDATE_INTERVAL        = 16.milliseconds
  LOOK_UPSAMPLING             = true
  DEFAULT_RENDER_DISTANCE     =      4
  DEFAULT_VIEW_DISTANCE       = 10_u32
  DEFAULT_SIMULATION_DISTANCE =  3_u32
  KEEP_ALIVE_INTERVAL         = 20.seconds
  INVENTORY_POLL_INTERVAL     = 1.second
  BOT_MONITOR_INTERVAL        = 50.milliseconds
  MAX_CONNECTIONS             = 10

  UNIMPLEMENTED_FORWARDED = {
    "set_entity_motion"            => {772_u32 => 0x5E_u32, 774_u32 => 0x63_u32, 775_u32 => 0x65_u32},
    "set_entity_data"              => {772_u32 => 0x5C_u32, 774_u32 => 0x61_u32, 775_u32 => 0x63_u32},
    "sound"                        => {772_u32 => 0x6E_u32, 774_u32 => 0x73_u32, 775_u32 => 0x75_u32},
    "update_attributes"            => {772_u32 => 0x7C_u32, 774_u32 => 0x81_u32, 775_u32 => 0x83_u32},
    "world_particles"              => {772_u32 => 0x29_u32, 774_u32 => 0x2E_u32, 775_u32 => 0x2F_u32},
    "explosion"                    => {772_u32 => 0x20_u32, 774_u32 => 0x24_u32, 775_u32 => 0x24_u32},
    "scoreboard_objective"         => {772_u32 => 0x63_u32, 774_u32 => 0x68_u32, 775_u32 => 0x6A_u32},
    "scoreboard_score"             => {772_u32 => 0x67_u32, 774_u32 => 0x6C_u32, 775_u32 => 0x6E_u32},
    "scoreboard_display_objective" => {772_u32 => 0x5B_u32, 774_u32 => 0x60_u32, 775_u32 => 0x62_u32},
    "reset_score"                  => {772_u32 => 0x48_u32, 774_u32 => 0x4D_u32, 775_u32 => 0x4F_u32},
    "teams"                        => {772_u32 => 0x66_u32, 774_u32 => 0x6B_u32, 775_u32 => 0x6D_u32},
    "set_title_text"               => {772_u32 => 0x6B_u32, 774_u32 => 0x70_u32, 775_u32 => 0x72_u32},
    "set_title_subtitle"           => {772_u32 => 0x69_u32, 774_u32 => 0x6E_u32, 775_u32 => 0x70_u32},
    "set_title_time"               => {772_u32 => 0x6C_u32, 774_u32 => 0x71_u32, 775_u32 => 0x73_u32},
    "clear_titles"                 => {772_u32 => 0x0E_u32, 774_u32 => 0x0E_u32, 775_u32 => 0x0E_u32},
    "action_bar"                   => {772_u32 => 0x50_u32, 774_u32 => 0x55_u32, 775_u32 => 0x57_u32},
    "playerlist_header"            => {772_u32 => 0x73_u32, 774_u32 => 0x78_u32, 775_u32 => 0x7A_u32},
    "hurt_animation"               => {772_u32 => 0x24_u32, 774_u32 => 0x29_u32, 775_u32 => 0x2A_u32},
    "damage_event"                 => {772_u32 => 0x19_u32, 774_u32 => 0x19_u32, 775_u32 => 0x19_u32},
    "entity_sound_effect"          => {772_u32 => 0x6D_u32, 774_u32 => 0x72_u32, 775_u32 => 0x74_u32},
    "entity_head_rotation"         => {772_u32 => 0x4C_u32, 774_u32 => 0x51_u32, 775_u32 => 0x53_u32},
    "entity_status"                => {772_u32 => 0x1E_u32, 774_u32 => 0x22_u32, 775_u32 => 0x22_u32},
    "initialize_world_border"      => {772_u32 => 0x25_u32, 774_u32 => 0x2A_u32, 775_u32 => 0x2B_u32},
    "world_border_center"          => {772_u32 => 0x51_u32, 774_u32 => 0x56_u32, 775_u32 => 0x58_u32},
    "world_border_lerp_size"       => {772_u32 => 0x52_u32, 774_u32 => 0x57_u32, 775_u32 => 0x59_u32},
    "world_border_size"            => {772_u32 => 0x53_u32, 774_u32 => 0x58_u32, 775_u32 => 0x5A_u32},
    "world_border_warning_delay"   => {772_u32 => 0x54_u32, 774_u32 => 0x59_u32, 775_u32 => 0x5B_u32},
    "world_border_warning_reach"   => {772_u32 => 0x55_u32, 774_u32 => 0x5A_u32, 775_u32 => 0x5C_u32},
    "world_event"                  => {772_u32 => 0x28_u32, 774_u32 => 0x2D_u32, 775_u32 => 0x2E_u32},
    "block_action"                 => {772_u32 => 0x07_u32, 774_u32 => 0x07_u32, 775_u32 => 0x07_u32},
    "tile_entity_data"             => {772_u32 => 0x06_u32, 774_u32 => 0x06_u32, 775_u32 => 0x06_u32},
    "experience"                   => {772_u32 => 0x60_u32, 774_u32 => 0x65_u32, 775_u32 => 0x67_u32},
    "set_cooldown"                 => {772_u32 => 0x16_u32, 774_u32 => 0x16_u32, 775_u32 => 0x16_u32},
    "collect"                      => {772_u32 => 0x75_u32, 774_u32 => 0x7A_u32, 775_u32 => 0x7C_u32},
    "attach_entity"                => {772_u32 => 0x5D_u32, 774_u32 => 0x62_u32, 775_u32 => 0x64_u32},
    "entity_teleport"              => {772_u32 => 0x76_u32, 774_u32 => 0x7B_u32, 775_u32 => 0x7D_u32},
    "commands"                     => {772_u32 => 0x10_u32, 774_u32 => 0x10_u32, 775_u32 => 0x10_u32},
  }.transform_values { |ids| ids.merge({773_u32 => ids[774_u32], 776_u32 => ids[775_u32]}) }

  macro build_forwarded_packets_method
    def self.forwarded_packets(protocol : UInt32) : Hash(UInt32, String)
      result = Hash(UInt32, String).new

      {% for klass in [
                        Clientbound::SystemChatMessage,
                        Clientbound::CloseWindow,
                        Clientbound::OpenWindow,
                        Clientbound::BlockChange,
                        Clientbound::MultiBlockChange,
                        Clientbound::SpawnEntity,
                        Clientbound::EntityPositionSync,
                        Clientbound::EntityPosition,
                        Clientbound::EntityRotation,
                        Clientbound::EntityPositionAndRotation,
                        Clientbound::EntityEquipment,
                        Clientbound::DestroyEntities,
                        Clientbound::PlayerInfoUpdate,
                        Clientbound::PlayerInfoRemove,
                        Clientbound::SetBlockDestroyStage,
                        Clientbound::UpdateHealth,
                        Clientbound::SetExperience,
                        Clientbound::EntityEffect,
                        Clientbound::RemoveEntityEffect,
                        Clientbound::SetTime,
                        Clientbound::EntityAnimation,
                        Clientbound::GameEvent,
                        Clientbound::SetPassengers,
                        Clientbound::SetContainerContent,
                        Clientbound::SetSlot,
                      ] %}
        result[{{klass}}[protocol]] = {{klass.name.split("::").last}}
      {% end %}

      UNIMPLEMENTED_FORWARDED.each do |name, ids|
        if id = ids[protocol]?
          result[id] = name
        end
      end

      result
    end
  end

  build_forwarded_packets_method

  Log = ::Log.for self

  property host : String
  property port : Int32
  property client : Rosegold::Client?
  property server : TCPServer?
  property connections = Array(Connection).new

  getter cached_commands_bytes : Bytes? = nil
  @bot_commands_handler_id : UUID? = nil

  @next_command_suggestion_tid = Atomic(UInt32).new(0_u32)

  @boss_bar_mutex = Mutex.new
  @boss_bar_uuid = UUID.random
  @boss_bar_active = false
  @last_action_bar : Rosegold::TextComponent? = nil
  @last_boss_bar_title : Rosegold::TextComponent? = nil
  @last_boss_bar_progress : Float32 = 0.0_f32
  @last_boss_bar_color : Clientbound::BossEvent::Color = Clientbound::BossEvent::Color::White
  @last_boss_bar_division : Clientbound::BossEvent::Division = Clientbound::BossEvent::Division::None

  @upstream_boss_bars = Hash(UUID, BossBarState).new
  @bot_boss_bar_handler_id : UUID? = nil
  @bot_disconnected_handler_id : UUID? = nil
  @bot_start_configuration_handler_id : UUID? = nil
  @client_generation = 0_u64

  def initialize(@host : String = "127.0.0.1", @port : Int32 = 25566)
  end

  def next_command_suggestion_tid : UInt32
    @next_command_suggestion_tid.add(1_u32) &+ 1_u32
  end

  # Broadcast a chat message to every spectating connection.
  def chat(message : String | Rosegold::TextComponent)
    broadcast(Clientbound::SystemChatMessage.new(as_text_component(message), false))
  end

  # Broadcast an action bar message to every spectating connection.
  # Sticky: replayed to spectators that join later, until replaced.
  def action_bar(text : String | Rosegold::TextComponent)
    component = as_text_component(text)
    @last_action_bar = component
    broadcast(Clientbound::SetActionBarText.new(component))
  end

  # Broadcast a boss bar update to every spectating connection.
  # Complete add packets also replace existing bars, avoiding vanilla crashes
  # if the client lost its prior state before an update.
  def boss_bar(
    title : String | Rosegold::TextComponent,
    progress : Float64,
    color : Clientbound::BossEvent::Color = Clientbound::BossEvent::Color::White,
    division : Clientbound::BossEvent::Division = Clientbound::BossEvent::Division::None,
  )
    component = as_text_component(title)
    health = progress.clamp(0.0, 1.0).to_f32

    @boss_bar_mutex.synchronize do
      if @boss_bar_active
        @last_boss_bar_title = component
        @last_boss_bar_progress = health
        @last_boss_bar_color = color
        @last_boss_bar_division = division
        broadcast_boss_bar_add(current_boss_bar_add, replace: true)
      else
        @boss_bar_active = true
        @last_boss_bar_title = component
        @last_boss_bar_progress = health
        @last_boss_bar_color = color
        @last_boss_bar_division = division
        broadcast_boss_bar_add(current_boss_bar_add)
      end
    end
  end

  # Convenience overload computing progress from current/max, clamped to 0..1.
  def boss_bar(
    title : String | Rosegold::TextComponent,
    current : Number,
    max : Number,
    color : Clientbound::BossEvent::Color = Clientbound::BossEvent::Color::White,
    division : Clientbound::BossEvent::Division = Clientbound::BossEvent::Division::None,
  )
    progress = max.to_f64 > 0 ? current.to_f64 / max.to_f64 : 0.0
    boss_bar(title, progress, color, division)
  end

  # Remove the boss bar from every spectating connection and clear stored state.
  def clear_boss_bar
    @boss_bar_mutex.synchronize do
      return unless @boss_bar_active
      broadcast_boss_bar_remove(@boss_bar_uuid)
      @boss_bar_active = false
      @last_boss_bar_title = nil
    end
  end

  # Replay stored action bar and boss bar state to a spectator that just joined.
  def replay_ui_state(connection : Connection, boss_bar_session : UInt64)
    return unless connection.boss_bar_session?(boss_bar_session)

    if text = @last_action_bar
      connection.send_packet(Clientbound::SetActionBarText.new(text))
    end

    @boss_bar_mutex.synchronize do
      return unless connection.boss_bar_session?(boss_bar_session)

      if @boss_bar_active
        connection.enqueue_boss_bar_add(current_boss_bar_add, boss_bar_session)
      end

      @upstream_boss_bars.each_value do |state|
        connection.enqueue_boss_bar_add(state.add_packet, boss_bar_session)
      end
    end
  end

  private def as_text_component(value : String | Rosegold::TextComponent) : Rosegold::TextComponent
    value.is_a?(String) ? Rosegold::TextComponent.new(value) : value
  end

  private def broadcast(packet : Clientbound::Packet)
    @connections.select(&.spectate_state.spectating?).each do |connection|
      connection.send_packet(packet)
    end
  end

  private def current_boss_bar_add : Clientbound::BossEvent
    title = @last_boss_bar_title || raise "Active boss bar requires title"
    Clientbound::BossEvent.add(@boss_bar_uuid, title, @last_boss_bar_progress, @last_boss_bar_color, @last_boss_bar_division)
  end

  private def broadcast_boss_bar_add(packet : Clientbound::BossEvent, replace : Bool = false)
    @connections.each do |connection|
      connection.enqueue_boss_bar_add(packet, replace: replace)
    end
  end

  private def broadcast_boss_bar_remove(uuid : UUID)
    @connections.each do |connection|
      connection.enqueue_boss_bar_remove(uuid)
    end
  end

  def start
    if (client = @client) && @bot_boss_bar_handler_id.nil?
      attach_client(client)
    end

    @server = TCPServer.new(host, port)
    Log.info { "SpectateServer listening on #{host}:#{port}" }

    spawn do
      while server = @server
        begin
          client_socket = server.accept

          @connections.reject! { |conn| !conn.connected? }

          if @connections.size >= MAX_CONNECTIONS
            Log.warn { "Max connections reached, rejecting #{client_socket.remote_address}" }
            client_socket.close
            next
          end

          enable_tcp_keepalive(client_socket)
          enable_tcp_nodelay(client_socket)

          Log.info { "New spectator connection from #{client_socket.remote_address}" }

          connection = Connection.new(client_socket, self)
          @connections << connection

          spawn do
            connection.handle_client
          rescue e
            Log.error { "Spectator connection error: #{e}" }
          ensure
            connection.close
            @connections.delete(connection)
          end
        rescue e : IO::Error
          Log.debug { "Server accept error: #{e}" }
          break if server.closed?
        end
      end
    end
  end

  def stop
    stop_caching_commands
    stop_tracking_boss_bars
    @boss_bar_mutex.synchronize do
      @client_generation &+= 1
      @upstream_boss_bars.clear
    end
    @server.try &.close
    @connections.dup.each(&.close)
    @connections.clear
  end

  private def enable_tcp_keepalive(socket : TCPSocket)
    socket.keepalive = true
    socket.tcp_keepalive_idle = 30
    socket.tcp_keepalive_interval = 10
    socket.tcp_keepalive_count = 3
  rescue ex
    Log.debug { "Failed to enable TCP keepalive: #{ex}" }
  end

  private def enable_tcp_nodelay(socket : TCPSocket)
    socket.tcp_nodelay = true
  rescue ex
    Log.debug { "Failed to enable TCP nodelay: #{ex}" }
  end

  def attach_client(client : Rosegold::Client)
    previous_client = @client
    stop_caching_commands
    stop_tracking_boss_bars
    @cached_commands_bytes = nil

    generation = @boss_bar_mutex.synchronize do
      @client_generation &+= 1
      @upstream_boss_bars.each_key { |uuid| broadcast_boss_bar_remove(uuid) }
      @upstream_boss_bars.clear
      @client = client
      @client_generation
    end

    if previous_client && !previous_client.same?(client)
      @connections.dup.each(&.detach_from_bot("Bot changed. Loading new world..."))
    end

    start_caching_commands(client)
    start_tracking_boss_bars(client, generation)
    sync_upstream_boss_bars(client, generation)
  end

  def detach_client
    stop_caching_commands
    stop_tracking_boss_bars
    @cached_commands_bytes = nil
    @client = nil
    @last_action_bar = nil
    @boss_bar_mutex.synchronize do
      @client_generation &+= 1
      if @boss_bar_active
        broadcast_boss_bar_remove(@boss_bar_uuid)
        @boss_bar_active = false
        @last_boss_bar_title = nil
      end
      @upstream_boss_bars.each_key do |uuid|
        broadcast_boss_bar_remove(uuid)
      end
      @upstream_boss_bars.clear
    end
    @connections.dup.each(&.detach_from_bot)
  end

  # Relay the upstream server's boss bars to spectators. Only packets for bars
  # the spectator has seen an add for may be sent: vanilla crashes on updates
  # for unknown boss bar UUIDs.
  private def handle_upstream_boss_event(client : Rosegold::Client, generation : UInt64, event : Clientbound::BossEvent)
    @boss_bar_mutex.synchronize do
      return unless @client.same?(client) && @client_generation == generation

      case event.action
      in .add?
        if state = client.boss_bar_state(event.uuid)
          replace = @upstream_boss_bars.has_key?(event.uuid)
          @upstream_boss_bars[event.uuid] = state
          broadcast_boss_bar_add(state.add_packet, replace: replace)
        end
      in .remove?
        broadcast_boss_bar_remove(event.uuid) if @upstream_boss_bars.delete(event.uuid)
      in .update_health?, .update_title?, .update_style?, .update_flags?
        if state = client.boss_bar_state(event.uuid)
          @upstream_boss_bars[event.uuid] = state
          broadcast_boss_bar_add(state.add_packet, replace: true)
        end
      end
    end
  end

  private def start_tracking_boss_bars(client : Rosegold::Client, generation : UInt64)
    return if @bot_boss_bar_handler_id

    @bot_boss_bar_handler_id = client.on(Clientbound::BossEvent) do |event|
      handle_upstream_boss_event(client, generation, event)
    end
    @bot_disconnected_handler_id = client.on(Event::Disconnected) do |_event|
      clear_upstream_boss_bars(client, generation)
    end
    @bot_start_configuration_handler_id = client.on(Clientbound::StartConfiguration) do |_event|
      clear_upstream_boss_bars(client, generation)
    end
  end

  private def sync_upstream_boss_bars(client : Rosegold::Client, generation : UInt64)
    @boss_bar_mutex.synchronize do
      return unless @client.same?(client) && @client_generation == generation

      @upstream_boss_bars.each_key { |uuid| broadcast_boss_bar_remove(uuid) }
      @upstream_boss_bars = client.boss_bar_states.to_h { |state| {state.uuid, state} }
      @upstream_boss_bars.each_value { |state| broadcast_boss_bar_add(state.add_packet) }
    end
  end

  private def clear_upstream_boss_bars(client : Rosegold::Client, generation : UInt64)
    @boss_bar_mutex.synchronize do
      return unless @client.same?(client) && @client_generation == generation

      @upstream_boss_bars.each_key { |uuid| broadcast_boss_bar_remove(uuid) }
      @upstream_boss_bars.clear
    end
  end

  private def stop_tracking_boss_bars
    if client = @client
      if id = @bot_boss_bar_handler_id
        client.off(Clientbound::BossEvent, id)
      end
      if id = @bot_disconnected_handler_id
        client.off(Event::Disconnected, id)
      end
      if id = @bot_start_configuration_handler_id
        client.off(Clientbound::StartConfiguration, id)
      end
    end
    @bot_boss_bar_handler_id = nil
    @bot_disconnected_handler_id = nil
    @bot_start_configuration_handler_id = nil
  end

  private def start_caching_commands(client : Rosegold::Client)
    return if @bot_commands_handler_id

    commands_pkt_id = UNIMPLEMENTED_FORWARDED["commands"][client.protocol_version]?
    return unless commands_pkt_id
    commands_id_byte = commands_pkt_id.to_u8

    @bot_commands_handler_id = client.on(Rosegold::Event::RawPacket) do |event|
      next unless event.bytes[0]? == commands_id_byte
      @cached_commands_bytes = event.bytes
      Log.debug { "Cached Commands packet (#{event.bytes.size} bytes)" }
    end
  end

  private def stop_caching_commands
    if (client = @client) && (id = @bot_commands_handler_id)
      client.off(Rosegold::Event::RawPacket, id)
    end
    @bot_commands_handler_id = nil
  end
end
