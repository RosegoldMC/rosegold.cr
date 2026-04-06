require "../packet"

class Rosegold::Serverbound::Pong < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x2C_u32, # MC 1.21.8
    774_u32 => 0x2C_u32, # MC 1.21.11
    775_u32 => 0x2D_u32, # MC 26.1
  })

  property ping_id : Int32

  def initialize(@ping_id : Int32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full ping_id
    end.to_slice
  end
end
