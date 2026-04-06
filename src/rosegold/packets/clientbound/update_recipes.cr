require "../packet"

class Rosegold::Clientbound::UpdateRecipes < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x7E_u32, # MC 1.21.8
    774_u32 => 0x83_u32, # MC 1.21.11
    775_u32 => 0x85_u32, # MC 26.1
  })

  def initialize; end

  def self.read(packet)
    # Skip all data — complex structure used for stonecutter/property sets
    # The bot uses RecipeBookAdd for available recipes instead
    self.new
  end

  def callback(client)
    Log.debug { "UpdateRecipes received (skipped)" }
  end
end
