require "compress/zlib"
require "../../minecraft/io"
require "./packet"
require "./clientbound/*"
require "./serverbound/*"

abstract class Rosegold::Event; end # defined elsewhere, but otherwise it would be a module

class Rosegold::Event::Disconnected < Rosegold::Event
  getter reason : Chat

  def initialize(@reason); end
end

# Something that packets can be read from and sent to.
# Can be used for client and server.
# Caller of #read_packet must update #state= appropriately.
# Useless after disconnect; create a new instance to reconnect.
class Rosegold::Connection(InboundPacket, OutboundPacket)
  alias Client = Connection(Clientbound::Packet, Serverbound::Packet)
  alias Server = Connection(Serverbound::Packet, Clientbound::Packet)

  property io : Minecraft::IO
  getter state : Hash(UInt8, InboundPacket.class)
  property handler : Rosegold::EventEmitter?

  property compression_threshold : UInt32 = 0
  property close_reason : Chat?
  private getter read_mutex : Mutex = Mutex.new
  private getter write_mutex : Mutex = Mutex.new

  def initialize(@io, @state, @handler = nil); end

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

  def open?
    !close_reason
  end

  def closed?
    !!close_reason
  end

  def disconnect(reason : Chat)
    Log.info { "Disconnected: #{reason}" }
    @close_reason = reason
    io.close
    handler.try &.emit_event Event::Disconnected.new reason
  end

  private def compress?
    compression_threshold.positive?
  end

  def read_packet : InboundPacket
    Connection.decode_packet read_raw_packet, state
  end

  def read_raw_packet : Bytes
    raise Rosegold::Client::NotConnected.new if close_reason

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
  rescue e
    disconnect Chat.new "IO Error: #{e.message}"
    raise_without_backtrace e
  end

  def self.decode_packet(
    packet_bytes : Bytes,
    state : Hash(UInt8, InboundPacket.class),
  ) : InboundPacket
    Minecraft::IO::Memory.new(packet_bytes).try do |pkt_io|
      pkt_id = pkt_io.read_byte || raise "Empty packet"
      pkt_type = state[pkt_id]?
      unless pkt_type && pkt_type.responds_to? :read
        return InboundPacket.new_raw(packet_bytes).as InboundPacket
      end
      pkt_type.read pkt_io
    end
  end

  def send_packet(packet : OutboundPacket)
    send_packet packet.write
  end

  def send_packet(packet_bytes : Bytes)
    raise Rosegold::Client::NotConnected.new if close_reason

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
    end.try do |bytes_compressed|
      write_mutex.synchronize do
        io.write bytes_compressed.size.to_u32
        io.write bytes_compressed
        io.flush
      end
    end
  rescue e
    disconnect Chat.new "IO Error: #{e.message}"
    raise_without_backtrace e
  end
end
