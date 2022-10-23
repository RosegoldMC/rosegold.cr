require "compress/zlib"
require "../../minecraft/io"
require "./packet"
require "./clientbound/*"
require "./serverbound/*"

# Can be used for client and server.
# Useless after disconnect; create a new instance to reconnect.
class Rosegold::Connection(InboundPacket, OutboundPacket)
  alias Client = Connection(Clientbound::Packet, Serverbound::Packet)
  alias Server = Connection(Serverbound::Packet, Clientbound::Packet)

  property io : Minecraft::IO
  getter state : Hash(UInt8, InboundPacket.class)

  property compression_threshold : UInt32 = 0
  property close_reason : String?
  private getter read_mutex : Mutex = Mutex.new
  private getter write_mutex : Mutex = Mutex.new

  def initialize(@io, @state); end

  def io=(io)
    read_mutex.synchronize do
      write_mutex.synchronize do
        @io = io
      end
    end
  end

  def state=(state)
    @state = state
  end

  def disconnect(reason : String)
    Log.info { "Disconnected: #{reason}" }
    @close_reason = reason
    io.close
  end

  private def compress?
    compression_threshold.positive?
  end

  def read_packet : InboundPacket?
    packet = decode_packet read_raw_packet
    Log.trace { "RECV " + inspect_packet(packet) }
    packet
  end

  def read_raw_packet : Bytes
    raise "Disconnected: #{close_reason}" if close_reason

    packet_bytes = Bytes.new 0
    read_mutex.synchronize do
      if compress?
        frame_len = io.read_var_int
        io.read_fully(frame_bytes = Bytes.new(frame_len))

        frame_io = Minecraft::IO::Memory.new frame_bytes
        uncompressed_data_len = frame_io.read_var_int
        if uncompressed_data_len == 0 # packet size is below compression_threshold
          uncompressed_data_len = frame_len - 1
        else # packet is in fact compressed
          frame_io = Compress::Zlib::Reader.new frame_io
        end
        frame_io.read_fully(packet_bytes = Bytes.new uncompressed_data_len)
      else
        io.read_fully(packet_bytes = Bytes.new io.read_var_int)
      end
    end
    packet_bytes
  rescue e : IO::EOFError
    @close_reason = "IO Error: #{e.message}"
    raise e
  end

  def decode_packet(packet_bytes : Bytes) : InboundPacket?
    Minecraft::IO::Memory.new(packet_bytes).try do |pkt_io|
      pkt_id = pkt_io.read_byte.not_nil!
      pkt_type = state[pkt_id]?
      return nil unless pkt_type
      return nil unless pkt_type.responds_to? :read
      packet = pkt_type.read pkt_io
    end
  end

  def send_packet(packet : OutboundPacket)
    Log.trace { "SEND " + inspect_packet(packet) }
    send_packet packet.write
  end

  def send_packet(packet_bytes : Bytes)
    raise "Disconnected: #{close_reason}" if close_reason

    if compress?
      Minecraft::IO::Memory.new.tap do |buffer|
        size = packet_bytes.size

        if size > compression_threshold
          buffer.write size.to_u32

          Compress::Zlib::Writer.open(buffer) do |zlib|
            zlib.write packet_bytes
          end
        else
          buffer.write 0_u32
          buffer.write packet_bytes
        end
      end.to_slice
    else
      packet_bytes
    end.try do |packet_bytes|
      write_mutex.synchronize do
        io.write packet_bytes.size.to_u32
        io.write packet_bytes
        io.flush
      end
    end
  rescue e : IO::Error
    @close_reason = "IO Error: #{e.message}"
    raise e
  end
end

private def inspect_packet(packet)
  packet.pretty_inspect(999, " ", 0).sub(/:0x\S+/, "") \
    .gsub(/Rosegold::|Clientbound::|Serverbound::/, "")
end
