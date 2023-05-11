require "../packet"

class Rosegold::Clientbound::EntityEffect < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x65_u8

  property \
    entity_id : UInt64,
    effect_id : UInt32,
    amplifier : UInt8,
    duration : UInt32,
    flags : UInt8

  def initialize(@entity_id, @effect_id, @amplifier, @duration, @flags); end

  def self.read(packet)
    self.new(
      packet.read_var_long,
      packet.read_var_int,
      packet.read_byte,
      packet.read_var_int,
      packet.read_byte
    )
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?
    effect = Rosegold::Effect.from_value effect_id

    if client.player.entity_id == entity_id
        return if client.player.effects.find { |active_effect| active_effect == effect }
        client.player.effects << effect
        return
    end

    if entity.nil?
      Log.warn { "Received entity effect packet for unknown entity ID #{entity_id}" }
      return
    end

    return if entity.effects.find { |active_effect| active_effect == effect }
    entity.effects << effect
  end
end
