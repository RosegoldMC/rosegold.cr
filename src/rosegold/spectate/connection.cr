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

  # Event handler IDs for cleanup
  @raw_packet_handler_id : UUID? = nil
  @position_handler_id : UUID? = nil
  @arm_swing_handler_id : UUID? = nil

  def initialize(raw_socket : TCPSocket, @spectate_server : Server)
    @socket = Minecraft::IO::Wrap.new(raw_socket)
    @protocol_state = ProtocolState::HANDSHAKING
    @client = @spectate_server.client
  end

  PROTOCOL_VERSION_NAMES = {
    772_u32 => "1.21.8",
    774_u32 => "1.21.11",
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

  private def cleanup_event_handlers
    bot = @client
    return unless bot

    @raw_packet_handler_id.try { |id| bot.off(Event::RawPacket, id) }
    @position_handler_id.try { |id| bot.off(Event::PlayerPositionUpdate, id) }
    @arm_swing_handler_id.try { |id| bot.off(Event::ArmSwing, id) }

    @raw_packet_handler_id = nil
    @position_handler_id = nil
    @arm_swing_handler_id = nil
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
