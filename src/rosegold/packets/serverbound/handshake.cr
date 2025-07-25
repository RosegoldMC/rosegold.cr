require "../packet"

class Rosegold::Serverbound::Handshake < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (same across all versions)
  packet_ids({
    772_u32 => 0x00_u8, # MC 1.21.8,
  })

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
      packet.read_ushort.to_i32,
      packet.read_var_int.to_i32
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(protocol_version)
      buffer.write protocol_version
      buffer.write server_address
      buffer.write_full server_port.to_u16
      buffer.write next_state
    end.to_slice
  end
end
