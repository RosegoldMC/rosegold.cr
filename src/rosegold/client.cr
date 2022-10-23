require "socket"
require "../minecraft/io"
require "./bot"
require "./control/*"
require "./packets/connection"
require "./packets/packet"
require "./world/*"

# Holds data kept between (re)connections.
class Rosegold::Client
  property host : String, port : UInt16
  property protocol_version = 758_u32
  getter connection : Connection::Client?

  property \
    player : Player = Player.new,
    dimension : World::Dimension = World::Dimension.new,
    physics : Physics

  property callbacks : Callbacks = Callbacks.new

  private alias Callbacks = Hash(Clientbound::Packet.class, Array(Proc(Clientbound::Packet, Nil)))

  def initialize(@host : String, @port : UInt16 = 25565)
    @physics = uninitialized Physics
    @physics = Physics.new self
  end

  def connection!
    @connection.not_nil!
  end

  def connected?
    @connection && !connection!.close_reason
  end

  def state=(state)
    connection!.state = state
  end

  def join_game
    connect

    until connection!.state == ProtocolState::PLAY.clientbound
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

    send_packet! Serverbound::Handshake.new protocol_version, host, port, 2
    connection.state = ProtocolState::LOGIN.clientbound

    queue_packet Serverbound::LoginStart.new ENV["MC_NAME"]

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
    raise "Already connected" if connected?

    io = Minecraft::IO::Wrap.new TCPSocket.new(host, port)
    connection = @connection = Connection::Client.new io, ProtocolState::HANDSHAKING.clientbound

    send_packet! Serverbound::Handshake.new protocol_version, host, port, 1
    connection.state = ProtocolState::STATUS.clientbound

    queue_packet Serverbound::StatusRequest.new

    read_packet
  end

  def on(packet_type : T.class, &block : T ->) forall T
    callbacks[packet_type] ||= [] of Proc(Clientbound::Packet, Nil)
    callbacks[packet_type] << Proc(Clientbound::Packet, Nil).new do |packet|
      block.call(packet.as T)
    end
  end

  # Send a packet to the server concurrently.
  def queue_packet(packet : Serverbound::Packet)
    raise "Not connected" unless connection
    spawn do
      Fiber.yield
      connection!.send_packet packet
    end
  end

  # Send a packet in the current fiber. Useful for things like
  # EncryptionRequest, because it must change the IO socket only AFTER
  # a EncryptionResponse has been sent.
  def send_packet!(packet : Serverbound::Packet)
    raise "Not connected" unless connection
    connection!.send_packet packet
  end

  private def read_packet
    raise "Not connected" unless connection
    packet = connection!.read_packet
    return nil unless packet

    packet.callback(self)

    callbacks[packet.class]?.try &.each &.call packet

    packet
  end
end
