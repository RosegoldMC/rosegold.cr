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
    read_mutex : Mutex = Mutex.new

  def initialize(@io : Minecraft::TCPSocket, @host : String, @port : UInt32)
  end

  def self.new(host : String, port : UInt32 = 25565)
    new(Minecraft::TCPSocket.new(host, port), host, port)
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

  def send_packet(packet : Rosegold::Serverbound::Packet)
    log_debug { "tx -> #{packet.class}".gsub "Rosegold::Serverbound::", "" }
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
      end.try do |serialized|
        io.write serialized.size.to_u32
        io.write serialized.to_slice
      end
    end
  end

  def read_packet
    if compress?
      frame_len = io.read_var_int
      # it's inconvenient to get the bytes length of uncompressed_data_len, so we just read it including the header
      io.read_fully(frame_bytes = Bytes.new(frame_len))
      frame_io = Minecraft::IO::Memory.new(frame_bytes)
      uncompressed_data_len = frame_io.read_var_int
      if uncompressed_data_len == 0 # packet size is below compression_threshold
        uncompressed_data_len = frame_len - 1
      else # packet is in fact compressed
        frame_io = Compress::Zlib::Reader.new(frame_io)
      end
      frame_io.read_fully(pkt_bytes = Bytes.new uncompressed_data_len)
    else # compression is disabled
      io.read_fully(pkt_bytes = Bytes.new io.read_var_int)
    end
    Minecraft::IO::Memory.new(pkt_bytes).try do |pkt_io|
      pkt_type = state[pkt_io.read_var_int]
      if pkt_type
        log_debug { "rx <- #{pkt_type}".gsub "Rosegold::Clientbound::", "" }
        return pkt_type.read(pkt_io).tap &.callback(self)
      else
        return nil # packet not parsed
      end
    end
  end

  def start
    send_packet Serverbound::Handshake.new(
      PROTOCOL_VERSION,
      host,
      port.to_u16,
      2.to_u8
    )

    self.state = State::Login.new
    state

    send_packet Serverbound::LoginStart.new ENV["MC_NAME"]

    # spawn do
    loop do
      read_mutex.synchronize do
        read_packet
      end
    end
    # end
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
