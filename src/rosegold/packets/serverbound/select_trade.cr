require "../packet"

class Rosegold::Serverbound::SelectTrade < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x32_u32, # MC 1.21.8
    774_u32 => 0x32_u32, # MC 1.21.11
    773_u32 => 0x32_u32, # MC 1.21.9
    775_u32 => 0x33_u32, # MC 26.1
    776_u32 => 0x33_u32, # MC 26.2
  })

  property selected_slot : Int32

  def initialize(@selected_slot : Int32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write selected_slot
    end.to_slice
  end
end
