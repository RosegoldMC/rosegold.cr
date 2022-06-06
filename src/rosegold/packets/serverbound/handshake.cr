require "./packet"

class Rosegold::Serverbound::Handshake < Rosegold::Serverbound::Packet
  PACKET_ID = 0x00u32

  property \
    protocol_version : UInt32,
    server_address,
    server_port,
    next_state

  def initialize(
    @protocol_version : UInt32,
    @server_address : String,
    @server_port : UInt16,
    @next_state : UInt32
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write protocol_version
      buffer.write server_address
      buffer.write_bytes server_port, IO::ByteFormat::BigEndian
      buffer.write next_state
    end
  end
end
