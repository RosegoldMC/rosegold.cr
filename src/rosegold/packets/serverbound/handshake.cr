require "../packet"

class Rosegold::Serverbound::Handshake < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x00_u8
  class_getter state = Rosegold::ProtocolState::HANDSHAKING

  property \
    protocol_version : UInt32,
    server_address : String,
    server_port : Int32,
    next_state : Int32

  def initialize(
    @protocol_version : UInt32,
    @server_address : String,
    @server_port : Int32,
    @next_state : Int32,
  ); end

  def self.read(packet)
    self.new(
      packet.read_var_int,
      packet.read_var_string,
      packet.read_ushort,
      packet.read_var_int
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write protocol_version
      buffer.write server_address
      buffer.write_full server_port.to_u16
      buffer.write next_state
    end.to_slice
  end
end
