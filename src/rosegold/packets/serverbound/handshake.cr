require "../packet"

class Rosegold::Serverbound::Handshake < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x00_u8
  protocol_state Rosegold::ProtocolState::HANDSHAKING

  property \
    protocol_version : UInt32,
    server_address : String,
    server_port : UInt16,
    next_state : UInt32

  def initialize(
    @protocol_version : UInt32,
    @server_address : String,
    @server_port : UInt16,
    @next_state : UInt32
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write protocol_version
      buffer.write server_address
      buffer.write_full server_port
      buffer.write next_state
    end.to_slice
  end
end
