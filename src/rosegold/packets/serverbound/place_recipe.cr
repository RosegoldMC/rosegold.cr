require "../packet"

class Rosegold::Serverbound::PlaceRecipe < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x26_u32, # MC 1.21.8
    774_u32 => 0x26_u32, # MC 1.21.11
    775_u32 => 0x27_u32, # MC 26.1
  })

  property container_id : UInt32
  property recipe : UInt32
  property? use_max_items : Bool

  def initialize(@container_id, @recipe, @use_max_items = false); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write container_id
      buffer.write recipe
      buffer.write use_max_items?
    end.to_slice
  end
end
