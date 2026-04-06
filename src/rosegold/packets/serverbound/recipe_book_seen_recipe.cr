require "../packet"

class Rosegold::Serverbound::RecipeBookSeenRecipe < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x2E_u32, # MC 1.21.8
    774_u32 => 0x2E_u32, # MC 1.21.11
    775_u32 => 0x2F_u32, # MC 26.1
  })

  property recipe : UInt32

  def initialize(@recipe); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write recipe
    end.to_slice
  end
end
