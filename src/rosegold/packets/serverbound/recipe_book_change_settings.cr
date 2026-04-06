require "../packet"

class Rosegold::Serverbound::RecipeBookChangeSettings < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x2D_u32, # MC 1.21.8
    774_u32 => 0x2D_u32, # MC 1.21.11
    775_u32 => 0x2E_u32, # MC 26.1
  })

  enum BookType
    Crafting; Furnace; BlastFurnace; Smoker
  end

  property book_type : BookType
  property? is_open : Bool
  property? is_filtering : Bool

  def initialize(@book_type, @is_open, @is_filtering); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write book_type.value.to_u32
      buffer.write is_open?
      buffer.write is_filtering?
    end.to_slice
  end
end
