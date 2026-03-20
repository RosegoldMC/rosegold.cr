require "../packet"
require "../../inventory/recipe"

class Rosegold::Clientbound::PlaceGhostRecipe < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x38_u32, # MC 1.21.8
    774_u32 => 0x3D_u32, # MC 1.21.11
  })

  property container_id : UInt32

  def initialize(@container_id); end

  def self.read(packet)
    container_id = packet.read_var_int
    # Must consume the RecipeDisplay from the packet stream even though we don't use it
    RecipeDisplay.read(packet)
    self.new(container_id)
  end

  def callback(client)
    Log.debug { "PlaceGhostRecipe: container=#{container_id}" }
  end
end
