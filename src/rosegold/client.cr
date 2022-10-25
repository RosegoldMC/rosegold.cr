require "socket"
require "../minecraft/io"
require "./bot"
require "./control/*"
require "./packets/connection"
require "./packets/packet"
require "./world/*"

# Holds world state (player, chunks, etc.)
# and control state (physics, open window, etc.).
# Can be reconnected.
class Rosegold::Client
  class_getter protocol_version = 758_u32

  property host : String, port : UInt16
  @connection : Connection::Client?

  property \
    online_players : Hash(UUID, PlayerList::Entry) = Hash(UUID, PlayerList::Entry).new,
    player : Player = Player.new,
    dimension : Dimension = Dimension.new,
    physics : Physics

  getter raw_packet_handlers : Array(Proc(Bytes, Nil)) = Array(Proc(Bytes, Nil)).new

  getter callbacks : Callbacks = Callbacks.new

  private alias Callbacks = Hash(Clientbound::Packet.class, Array(Proc(Clientbound::Packet, Nil)))

  def initialize(@host : String, @port : UInt16 = 25565)
    @physics = uninitialized Physics
    @physics = Physics.new self
  end

  # Raises an error if this client has never been connected
  def connection
    @connection.not_nil!
  end

  def connected?
    @connection && !connection.close_reason
  end

  def state=(state)
    connection.state = state
  end

  def join_game
    connect

    until connection.state == ProtocolState::PLAY.clientbound
      sleep 0.1
    end
    Log.info { "Ingame" }

    bot = Bot.new self
    with bot yield bot
  end

  def connect
    raise "Already connected" if connected?

    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = @connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound
    Log.info { "Connected to #{host}:#{port}" }

    send_packet! Serverbound::Handshake.new Client.protocol_version, host, port, 2
    connection.state = ProtocolState::LOGIN.clientbound

    queue_packet Serverbound::LoginStart.new ENV["MC_NAME"]

    @online_players = Hash(UUID, PlayerList::Entry).new

    spawn do
      loop do
        if connection.close_reason
          Fiber.yield
          Log.info { "Stopping reader: #{connection.close_reason}" }
          break
        end
        read_packet
      end
    end
  end

  def status
    self.class.status host, port
  end

  def self.status(host : String, port : UInt16 = 25565)
    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound

    connection.send_packet Serverbound::Handshake.new Client.protocol_version, host, port, 1
    connection.state = ProtocolState::STATUS.clientbound

    connection.send_packet Serverbound::StatusRequest.new
    connection.read_packet.not_nil!
  end

  def on(packet_type : T.class, &block : T ->) forall T
    callbacks[packet_type] ||= [] of Proc(Clientbound::Packet, Nil)
    callbacks[packet_type] << Proc(Clientbound::Packet, Nil).new do |packet|
      block.call(packet.as T)
    end
  end

  # Send a packet to the server concurrently.
  def queue_packet(packet : Serverbound::Packet)
    raise "Not connected" unless connected?
    spawn do
      Fiber.yield
      send_packet! packet
    end
  end

  # Send a packet in the current fiber. Useful for things like
  # EncryptionRequest, because it must change the IO socket only AFTER
  # a EncryptionResponse has been sent.
  def send_packet!(packet : Serverbound::Packet)
    raise "Not connected" unless connected?
    Log.trace { "SEND " + inspect_packet(packet) }
    connection.send_packet packet
  end

  private def read_packet
    raise "Not connected" unless connected?
    raw_packet = connection.read_raw_packet

    raw_packet_handlers.each &.call raw_packet

    packet = Connection.decode_packet raw_packet, connection.state
    return nil unless packet
    Log.trace { "RECV " + inspect_packet(packet) }

    packet.callback(self)

    callbacks[packet.class]?.try &.each &.call packet

    packet
  end
end

private def inspect_packet(packet)
  packet.pretty_inspect(999, " ", 0).sub(/:0x\S+/, "") \
    .gsub(/Rosegold::|Clientbound::|Serverbound::/, "")
end
