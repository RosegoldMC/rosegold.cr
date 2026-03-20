require "../packet"

class Rosegold::Clientbound::RecipeBookSettings < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x45_u32, # MC 1.21.8
    774_u32 => 0x4A_u32, # MC 1.21.11
  })

  property? crafting_open : Bool
  property? crafting_filtering : Bool
  property? smelting_open : Bool
  property? smelting_filtering : Bool
  property? blast_furnace_open : Bool
  property? blast_furnace_filtering : Bool
  property? smoker_open : Bool
  property? smoker_filtering : Bool

  def initialize(@crafting_open, @crafting_filtering,
                 @smelting_open, @smelting_filtering,
                 @blast_furnace_open, @blast_furnace_filtering,
                 @smoker_open, @smoker_filtering); end

  def self.read(packet)
    self.new(
      packet.read_bool, packet.read_bool,
      packet.read_bool, packet.read_bool,
      packet.read_bool, packet.read_bool,
      packet.read_bool, packet.read_bool,
    )
  end

  def callback(client)
    Log.debug { "RecipeBookSettings received" }
  end
end
