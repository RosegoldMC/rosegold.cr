require "../packet"

class Rosegold::Clientbound::RemoveEntityEffect < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x3B_u8

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
    effect = Rosegold::Effect.from_value effect_id

    if client.player.entity_id == entity_id
        client.player.effects.delete effect
        return
    end

    if entity.nil?
      Log.warn { "Received entity effect packet for unknown entity ID #{entity_id}" }
      return
    end

    entity.effects.delete effect
  end
end
