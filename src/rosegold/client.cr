require "socket"
require "../minecraft/io"
require "../minecraft/auth"
require "./control/*"
require "./models/*"
require "./packets/*"
require "./events/*"
require "./world/*"

class Rosegold::Event::RawPacket < Rosegold::Event
  getter bytes : Bytes

  def initialize(@bytes); end
end

# Holds world state (player, chunks, etc.)
# and control state (physics, open window, etc.).
# Can be reconnected.
class Rosegold::Client < Rosegold::EventEmitter
  class_getter protocol_version = 771_u32 # Default to 1.21.6 (protocol 771)

  def self.protocol_version=(version : UInt32)
    @@protocol_version = version
  end

  property host : String, port : Int32
  property connection : Connection::Client?
  property detected_protocol_version : UInt32?
  property current_protocol_state : ProtocolState = ProtocolState::HANDSHAKING

  property \
    online_players : Hash(UUID, PlayerList::Entry) = Hash(UUID, PlayerList::Entry).new,
    player : Player = Player.new,
    access_token : String = "",
    dimension : Dimension = Dimension.new,
    physics : Physics,
    interactions : Interactions,
    inventory : PlayerWindow,
    window : Window,
    offline : NamedTuple(uuid: String, username: String)? = nil

  def protocol_version
    detected_protocol_version || Client.protocol_version
  end

  def initialize(@host : String, @port : Int32 = 25565, @offline : NamedTuple(uuid: String, username: String)? = nil)
    if host.includes? ":"
      @host, port_str = host.split ":"
      @port = port_str.to_i
    end
    @physics = uninitialized Physics
    @interactions = uninitialized Interactions
    @inventory = uninitialized PlayerWindow
    @window = uninitialized Window
    @physics = Physics.new self
    @interactions = Interactions.new self
    @inventory = PlayerWindow.new self
    @window = @inventory
  end

  def connection? : Connection::Client?
    @connection
  end

  def connection : Connection::Client
    conn = @connection
    raise NotConnected.new "Client was never connected" unless conn
    raise NotConnected.new "Disconnected: #{conn.close_reason}" if conn.close_reason
    conn
  end

  def connected?
    @connection.try &.open?
  end

  def state=(state)
    connection.state = state
  end

  def set_protocol_state(protocol_state : ProtocolState)
    @current_protocol_state = protocol_state
    connection.state = protocol_state.clientbound_for_protocol(protocol_version)
  end

  def spawned?
    inventory.ready? && !physics.paused? && connected?
  end

  # Waits for the client to be fully spawned, ie. physics and inventory being ready.
  def join_game(timeout_ticks = 1200)
    connect
    until spawned?
      sleep 1/20
      timeout_ticks -= 1
      raise NotConnected.new "Disconnected while joining game: #{connection.close_reason}" unless connected?
      raise NotConnected.new "Took too long to join the game" if timeout_ticks <= 0
    end

    start_ticker

    self
  end

  def join_game(*args, &)
    join_game(*args)
    yield self
    connection?.try &.disconnect Chat.new "End of script"

    self
  end

  def start_ticker
    spawn do
      loop do
        sleep 1.tick

        break unless connected?

        spawn do
          interactions.tick
          physics.tick
          emit_event Event::Tick.new
        end
      end
    end
  end

  def connect
    raise NotConnected.new "Already connected" if connected?

    authenticate!

    # Auto-detect server protocol version before connecting
    detect_and_set_protocol_version

    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = @connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound_for_protocol(protocol_version), self
    @current_protocol_state = ProtocolState::HANDSHAKING
    connection.handler.try &.on Event::Disconnected do |_event|
      physics.handle_disconnect
    end
    Log.info { "Connected to #{host}:#{port}" }

    send_packet! Serverbound::Handshake.new protocol_version, host, port, 2
    set_protocol_state(ProtocolState::LOGIN)

    queue_packet Serverbound::LoginStart.new player.username.not_nil!, player.uuid, protocol_version # ameba:disable Lint/NotNil

    @online_players = Hash(UUID, PlayerList::Entry).new

    spawn do
      while connected?
        read_packet
      end
    rescue e : IO::Error
      Log.debug { "Stopping reader: #{e}" }
    end
  end

  private def authenticate!
    offline.try do |offline|
      player.uuid = UUID.new offline[:uuid]
      player.username = offline[:username]
      return
    end

    Minecraft::Auth.new.authenticate.try do |auth|
      player.uuid = UUID.new auth["uuid"] || "00000000-0000-0000-0000-000000000000"
      player.username = auth["mc_name"] || "Player"
      self.access_token = auth["access_token"] || ""
    end
  end

  private def detect_and_set_protocol_version
    # Ping the server to get its protocol version
    # We'll try with a commonly supported protocol first, then adjust
    status_response = status
    if protocol_info = status_response.json_response["version"]?
      if server_protocol = protocol_info["protocol"]?.try(&.as_i?)
        Log.info { "Detected server protocol version: #{server_protocol}" }
        @detected_protocol_version = server_protocol.to_u32
      else
        Log.warn { "Could not parse protocol version from server status, using default" }
      end
    else
      Log.warn { "Server status response missing version info, using default" }
    end
  rescue e
    Log.warn { "Failed to detect server protocol version: #{e}, using default" }
  end

  def status
    self.class.status host, port.to_u16
  end

  def self.status(host : String, port : UInt16 = 25565)
    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound_for_protocol(Client.protocol_version)

    connection.send_packet Serverbound::Handshake.new Client.protocol_version, host, port, 1
    connection.state = ProtocolState::STATUS.clientbound_for_protocol(Client.protocol_version)

    connection.send_packet Serverbound::StatusRequest.new
    packet = connection.read_packet

    # Return the StatusResponse if it's the right type
    if packet.is_a?(Clientbound::StatusResponse)
      packet
    else
      raise "Unexpected packet type: #{packet.class}"
    end
  end

  # Send a packet to the server concurrently.
  def queue_packet(packet : Serverbound::Packet)
    spawn do
      Fiber.yield
      send_packet! packet
    rescue e : NotConnected
      Log.warn { "Not connected, not sending queued #{packet}" }
    end
  end

  # Send a packet in the current fiber. Useful for things like
  # EncryptionRequest, because it must change the IO socket only AFTER
  # a EncryptionResponse has been sent.
  def send_packet!(packet : Serverbound::Packet)
    raise NotConnected.new unless connected?
    Log.trace { "SEND #{packet}" }
    connection.send_packet packet
  end

  private def read_packet
    raise NotConnected.new unless connected?
    raw_packet = connection.read_raw_packet

    emit_event Event::RawPacket.new raw_packet

    Log.trace { "RECV 0x#{raw_packet[0].to_s 16}" }
    
    # Use protocol-aware decoding
    packet = Connection::Client.decode_packet(
      raw_packet,
      current_protocol_state,
      protocol_version,
      :clientbound
    ).as(Clientbound::Packet)
    
    Log.trace { "DECODE 0x#{raw_packet[0].to_s 16} #{packet}" }

    packet.callback(self)

    emit_event packet

    packet
  end

  class NotConnected < Exception; end
end
