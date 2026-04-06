require "../packet"

class Rosegold::Clientbound::RemoveEntityEffect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x47_u32, # MC 1.21.8
    774_u32 => 0x4C_u32, # MC 1.21.11
    775_u32 => 0x4E_u32, # MC 26.1
  })

  property \
    entity_id : UInt64,
    effect_id : UInt32

  def initialize(@entity_id, @effect_id); end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    effect_id = packet.read_var_int

    self.new(entity_id, effect_id)
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
