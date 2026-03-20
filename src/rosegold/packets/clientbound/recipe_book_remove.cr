require "../packet"

class Rosegold::Clientbound::RecipeBookRemove < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x44_u32, # MC 1.21.8
    774_u32 => 0x49_u32, # MC 1.21.11
  })

  property recipes : Array(UInt32)

  def initialize(@recipes); end

  def self.read(packet)
    count = packet.read_var_int
    recipes = Array(UInt32).new(count.to_i32)
    count.times { recipes << packet.read_var_int }
    self.new(recipes)
  end

  def callback(client)
    client.recipe_registry.remove(recipes)
    Log.debug { "RecipeBookRemove: #{recipes.size} recipes" }
  end
end
