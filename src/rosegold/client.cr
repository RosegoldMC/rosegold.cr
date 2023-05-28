require "socket"
require "../minecraft/io"
require "../minecraft/auth"
require "./control/*"
require "./models/*"
require "./packets/*"
require "./world/*"

abstract class Rosegold::Event; end # defined elsewhere, but otherwise it would be a module

class Rosegold::Event::RawPacket < Rosegold::Event
  getter bytes : Bytes

  def initialize(@bytes); end
end

# Holds world state (player, chunks, etc.)
# and control state (physics, open window, etc.).
# Can be reconnected.
class Rosegold::Client < Rosegold::EventEmitter
  class_getter protocol_version = 758_u32

  property host : String, port : Int32
  property connection : Connection::Client?
  property proxy : TCPServer?

  property \
    online_players : Hash(UUID, PlayerList::Entry) = Hash(UUID, PlayerList::Entry).new,
    player : Player = Player.new,
    access_token : String = "",
    dimension : Dimension = Dimension.new,
    physics : Physics,
    inventory : PlayerWindow,
    window : Window,
    offline : NamedTuple(uuid: String, username: String)? = nil

  def initialize(@host : String, @port : Int32 = 25565, @offline : NamedTuple(uuid: String, username: String)? = nil)
    if host.includes? ":"
      @host, port_str = host.split ":"
      @port = port_str.to_i
    end
    @physics = uninitialized Physics
    @inventory = uninitialized PlayerWindow
    @window = uninitialized Window
    @physics = Physics.new self
    @inventory = PlayerWindow.new self
    @window = @inventory
    start_proxy
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

  def start_proxy : TCPServer
    proxy = @proxy ||= TCPServer.new "localhost", 1234
    spawn do
      while socket = proxy.accept?
        puts "WHOA"
        spawn do
          server = Connection::Server.new Minecraft::IO::Wrap.new(socket), ProtocolState::LOGIN.serverbound
          server.state = ProtocolState::LOGIN.serverbound
          server.send_packet Clientbound::LoginStart.new player.username.not_nil! # ameba:disable Lint/NotNil
        end
      end
    end
  end

  def connected?
    @connection.try &.open?
  end

  def state=(state)
    connection.state = state
  end

  def spawned?
    inventory.ready? && !physics.paused? && connected?
  end

  # Waits for the client to be fully spawned, ie. physics and inventory being ready.
  def join_game(timeout_ticks = 1200)
    connect
    start_proxy
    Log.info { "Connect to localhost:1234 to spectate Rosegold bot" }
    until spawned?
      sleep 1/20
      timeout_ticks -= 1
      raise NotConnected.new "Disconnected while joining game: #{connection.close_reason}" unless connected?
      raise NotConnected.new "Took too long to join the game" if timeout_ticks <= 0
    end
  end

  def join_game(*args, &)
    join_game(*args)
    yield self
    connection?.try &.disconnect Chat.new "End of script"
  end

  def connect
    raise NotConnected.new "Already connected" if connected?

    authenticate!

    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = @connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound, self
    Log.info { "Connected to #{host}:#{port}" }

    send_packet! Serverbound::Handshake.new Client.protocol_version, host, port, 2
    connection.state = ProtocolState::LOGIN.clientbound

    queue_packet Serverbound::LoginStart.new player.username.not_nil! # ameba:disable Lint/NotNil

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

  delegate disconnect, to: connection

  def status
    self.class.status host, port
  end

  def self.status(host : String, port : UInt16 = 25565)
    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound

    connection.send_packet Serverbound::Handshake.new Client.protocol_version, host, port, 1
    connection.state = ProtocolState::STATUS.clientbound

    connection.send_packet Serverbound::StatusRequest.new
    connection.read_packet
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

    packet = Connection::Client.decode_packet raw_packet, connection.state
    Log.trace { "RECV 0x#{raw_packet[0].to_s 16} #{packet}" }

    packet.callback(self)

    emit_event packet

    packet
  end

  class NotConnected < Exception; end
end
