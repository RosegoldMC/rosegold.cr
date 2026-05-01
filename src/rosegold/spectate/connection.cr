require "./handshake"
require "./configuration"
require "./world_sync"
require "./play_session"
require "./monitoring"
require "./packet_relay"
require "./lobby"

enum Rosegold::Spectate::State
  LOBBY
  SPECTATING
end

class Rosegold::Spectate::Connection
  include Spectate::Handshake
  include Spectate::Configuration
  include Spectate::WorldSync
  include Spectate::PlaySession
  include Spectate::Monitoring
  include Spectate::PacketRelay
  include Spectate::Lobby

  Log = ::Log.for self

  property socket : Minecraft::IO::Wrap
  property spectate_server : Server
  property protocol_state : ProtocolState
  property client : Rosegold::Client?
  property username : String = "SpectatorBot"
  property uuid : UUID = UUID.random
  property keep_alive_id : Int64 = 0_i64
  property loaded_chunks : Set(Tuple(Int32, Int32)) = Set(Tuple(Int32, Int32)).new
  property teleport_id : UInt32 = 1_u32
  property? connected : Bool = true
  property spectate_state : State = State::LOBBY
  property last_digging_block : Vec3i? = nil
  property last_dig_progress : Float32 = 0.0_f32
  @handshake_protocol : UInt32 = 0_u32
  @keep_alive_running : Bool = false
  @packet_send_mutex = Mutex.new
  @transition_mutex = Mutex.new

  @bot_handler_cleanups : Array(->) = [] of ->

  COMMAND_SUGGESTION_MAP_LIMIT = 256
  @command_suggestion_map : Hash(UInt32, UInt32) = {} of UInt32 => UInt32
  @command_suggestion_map_mutex = Mutex.new

  def initialize(raw_socket : TCPSocket, @spectate_server : Server)
    @socket = Minecraft::IO::Wrap.new(raw_socket)
    @protocol_state = ProtocolState::HANDSHAKING
    @client = @spectate_server.client
  end

  PROTOCOL_VERSION_NAMES = {
    772_u32 => "1.21.8",
    774_u32 => "1.21.11",
    775_u32 => "26.1",
  }

  def protocol_version : UInt32
    @client.try(&.protocol_version) || Client.protocol_version
  end

  private def protocol_version_name : String
    PROTOCOL_VERSION_NAMES[protocol_version]? || "1.21.11"
  end

  def handle_client
    Log.debug { "Starting spectator client handler" }

    loop do
      break unless @connected
      packet_data = read_raw_packet
      packet = Rosegold::Connection.decode_serverbound_packet(packet_data, @protocol_state, protocol_version)
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
      when Rosegold::Serverbound::KnownPacks
        handle_known_packs_response(packet)
      when Rosegold::Serverbound::FinishConfiguration
        handle_finish_configuration
      when Rosegold::Serverbound::ConfigurationKeepAlive
        Log.trace { "Received configuration keep alive response" }
      when Rosegold::Serverbound::KeepAlive
        handle_keep_alive(packet)
      when Rosegold::Serverbound::TeleportConfirm
        Log.trace { "Received teleport confirm: #{packet.teleport_id}" }
      when Rosegold::Serverbound::ChatMessage
        handle_chat_message(packet)
      when Rosegold::Serverbound::ChatCommand
        handle_chat_command(packet)
      when Rosegold::Serverbound::CommandSuggestionsRequest
        handle_command_suggestions_request(packet)
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
    size = socket.read_var_int
    raise IO::Error.new("Packet too large: #{size}") if size > 2_097_151 || size < 0
    packet_bytes = Bytes.new(size)
    socket.read_fully(packet_bytes)
    packet_bytes
  rescue e : IO::Error
    raise e
  end

  def send_packet(packet : Rosegold::Clientbound::Packet)
    return unless @connected
    Log.trace { "SEND #{packet}" }

    @packet_send_mutex.synchronize do
      return unless @connected
      data = packet.write
      Log.debug { "SEND pkt=#{packet.class.name.split("::").last} len=#{data.size} first_bytes=#{data[0, Math.min(16, data.size)].hexstring}" }
      socket.write(data.size)
      socket.write(data)
      socket.flush
    end
  rescue ex : IO::Error
    Log.debug { "Failed to send packet: #{ex}" }
  rescue ex
    Log.error { "Packet send error: #{ex}" }
  end

  def close
    return unless @connected
    @connected = false
    cleanup_event_handlers
    @socket.close
  rescue
    # Socket already closed
  end

  protected def track_bot_handler(event_type : T.class, &block : T ->) forall T
    bot = @client
    return unless bot
    id = bot.on(event_type, &block)
    @bot_handler_cleanups << -> { bot.off(event_type, id) }
  end

  private def cleanup_event_handlers
    @bot_handler_cleanups.each(&.call)
    @bot_handler_cleanups.clear
    @command_suggestion_map_mutex.synchronize { @command_suggestion_map.clear }
  end

  private def handle_chat_message(packet : Rosegold::Serverbound::ChatMessage)
    return unless @spectate_state.spectating?
    bot = @client
    return unless bot && bot.connected?

    Log.debug { "Forwarding spectator chat: #{packet.message}" }
    bot.chat_manager.send_message(packet.message)
  rescue ex
    Log.error { "Failed to forward spectator chat: #{ex}" }
  end

  private def handle_chat_command(packet : Rosegold::Serverbound::ChatCommand)
    return unless @spectate_state.spectating?
    bot = @client
    return unless bot && bot.connected?

    Log.debug { "Forwarding spectator command: #{packet.command}" }
    bot.chat_manager.send_command(packet.command)
  rescue ex
    Log.error { "Failed to forward spectator command: #{ex}" }
  end

  private def handle_command_suggestions_request(packet : Rosegold::Serverbound::CommandSuggestionsRequest)
    return unless @spectate_state.spectating?
    bot = @client
    return unless bot && bot.connected?

    bot_tid = @spectate_server.next_command_suggestion_tid
    @command_suggestion_map_mutex.synchronize do
      # Bound map growth: a server that drops suggestion requests would otherwise leak entries indefinitely.
      if @command_suggestion_map.size >= COMMAND_SUGGESTION_MAP_LIMIT
        @command_suggestion_map.delete(@command_suggestion_map.first_key)
      end
      @command_suggestion_map[bot_tid] = packet.transaction_id
    end

    Log.debug { "Forwarding spectator command suggestions request: tid=#{packet.transaction_id} -> bot_tid=#{bot_tid} text=#{packet.text}" }
    bot.send_packet!(Rosegold::Serverbound::CommandSuggestionsRequest.new(bot_tid, packet.text))
  rescue ex
    Log.error { "Failed to forward spectator command suggestions request: #{ex}" }
  end

  def client_ready?
    @spectate_server.client.try &.spawned? || false
  end

  def self.decode_varint(bytes : Bytes) : UInt32?
    result = 0_u32
    shift = 0
    bytes.each do |byte|
      result |= ((byte & 0x7F).to_u32) << shift
      return result if byte & 0x80 == 0
      shift += 7
      return nil if shift >= 32
    end
    nil
  end
end
