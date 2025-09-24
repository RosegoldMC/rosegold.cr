require "../packet"

# Player Loaded packet
# Sent by the client to indicate that it is ready to start simulating the player.
# The vanilla client sends this when the "Loading terrain..." screen is closed.
#
# The vanilla client skips ticking the player entity until the tick on which this packet is sent.
# Other entities and objects will still be ticked.
class Rosegold::Serverbound::PlayerLoaded < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Resource name constant for debugging
  RESOURCE_NAME = "minecraft:player_loaded"

  packet_ids({
    772_u32 => 0x2B_u8, # MC 1.21.8
  })

  def initialize
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # No fields - this is an empty packet
    end.to_slice
  end
end
