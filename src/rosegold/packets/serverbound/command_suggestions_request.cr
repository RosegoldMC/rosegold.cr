require "../packet"

class Rosegold::Serverbound::CommandSuggestionsRequest < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x0E_u32,
    774_u32 => 0x0E_u32,
    775_u32 => 0x0E_u32,
  })

  property transaction_id : UInt32
  property text : String

  def initialize(@transaction_id : UInt32, @text : String); end

  def self.read(io)
    transaction_id = io.read_var_int
    text = io.read_var_string
    self.new(transaction_id, text)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write transaction_id
      buffer.write text
    end.to_slice
  end
end
