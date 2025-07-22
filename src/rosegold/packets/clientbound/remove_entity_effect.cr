require "../packet"

class Rosegold::Clientbound::RemoveEntityEffect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x3B_u8, # MC 1.18
    767_u32 => 0x3B_u8, # MC 1.21
    769_u32 => 0x3B_u8, # MC 1.21.4,
    771_u32 => 0x3B_u8, # MC 1.21.6,
  })

  property \
    entity_id : UInt64,
    effect_id : UInt32

  def initialize(@entity_id, @effect_id); end

  def self.read(packet)
    self.new(
      packet.read_var_long,
      packet.read_var_int,
    )
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?

    if client.player.entity_id == entity_id
      client.player.effects = client.player.effects.reject { |effect| effect.id == effect_id }
      return
    end

    if entity.nil?
      Log.warn { "Received RemoveEntityEffect packet for unknown entity ID #{entity_id}" }
      return
    end

    entity.effects = entity.effects.reject { |effect| effect.id == effect_id }
  end
end
