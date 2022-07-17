require "compress/zlib"
require "socket"
require "../minecraft/*"
require "./packets/clientbound/packet"
require "./packets/clientbound/*"
require "./packets/serverbound/*"
require "./states"

class Rosegold::Client
  PROTOCOL_VERSION = 758_u32

  property \
    io : Minecraft::TCPSocket | Minecraft::EncryptedTCPSocket,
    host : String,
    port : UInt32,
    state : State::Status | State::Login | State::Play = State::Status.new,
    compression_threshold : UInt32 = 0,
    read_mutex : Mutex = Mutex.new,
    write_mutex : Mutex = Mutex.new

  def initialize(@io : Minecraft::TCPSocket, @host : String, @port : UInt32)
  end

  def self.new(host : String, port : UInt32 = 25565)
    new(Minecraft::TCPSocket.new(host, port), host, port)
  end

  def state=(state)
    read_mutex.synchronize do
      @state = state
    end
  end

  def log_info(&build_msg : -> String)
    STDERR.puts build_msg.call
  end

  def log_debug(&build_msg : -> String)
    # STDERR.puts build_msg.call
  end

  def compress?
    compression_threshold.positive?
  end

  # Used to send a packet to the server concurrently
  def queue_packet(packet : Rosegold::Serverbound::Packet)
    spawn do
      Fiber.yield
      send_packet packet
    end
  end

  # Used to send a packet in the current fiber, useful for things like
  # EncryptionRequest, because it must change the IO socket only AFTER
  # a EncryptionResponse has been sent
  def send_packet!(packet : Rosegold::Serverbound::Packet)
    send_packet packet
  end

  private def send_packet(packet : Rosegold::Serverbound::Packet)
    packet.to_packet.try do |packet|
      if compress?
        Minecraft::IO::Memory.new.tap do |buffer|
          size = packet.to_slice.size

          if size > compression_threshold
            buffer.write size.to_u32

            Compress::Zlib::Writer.open(buffer) do |zlib|
              zlib.write packet.to_slice
            end
          else
            buffer.write 0_u32
            buffer.write packet.to_slice
          end
        end
      else
        packet
      end
    end.try do |packet|
      write_mutex.synchronize do
        io.write packet.size.to_u32
        io.write packet.to_slice
        io.flush
      end
    end
  end

  def read_packet
    current_state = state
    pkt_bytes = Bytes.new 0

    read_mutex.synchronize do
      current_state = state
      if compress?
        frame_len = io.read_var_int
        io.read_fully(frame_bytes = Bytes.new(frame_len))

        frame_io = Minecraft::IO::Memory.new(frame_bytes)
        uncompressed_data_len = frame_io.read_var_int
        if uncompressed_data_len == 0 # packet size is below compression_threshold
          uncompressed_data_len = frame_len - 1
        else # packet is in fact compressed
          frame_io = Compress::Zlib::Reader.new(frame_io)
        end
        frame_io.read_fully(pkt_bytes = Bytes.new uncompressed_data_len)
      else
        io.read_fully(pkt_bytes = Bytes.new io.read_var_int)
      end
    end

    Minecraft::IO::Memory.new(pkt_bytes).try do |pkt_io|
      pkt_type = current_state[pkt_io.read_var_int]
      if pkt_type
        log_debug { "rx <- #{pkt_type}".gsub "Rosegold::Clientbound::", "" }
        pkt_type.read(pkt_io).tap &.callback(self)
      else
        nil # packet not parsed
      end
    end
  end

  def start
    queue_packet Serverbound::Handshake.new(
      PROTOCOL_VERSION,
      host,
      port.to_u16,
      2.to_u8
    )

    self.state = State::Login.new

    queue_packet Serverbound::LoginStart.new ENV["MC_NAME"]

    spawn do
      loop do
        read_packet
      end
    end

    sleep
  end

  def status
    send_packet Serverbound::Handshake.new(
      PROTOCOL_VERSION,
      host,
      port.to_u16,
      1.to_u8
    )

    send_packet Serverbound::Status.new

    read_packet
  end
end
