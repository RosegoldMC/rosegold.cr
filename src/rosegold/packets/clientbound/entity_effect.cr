require "../packet"

class Rosegold::Clientbound::EntityEffect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x7D_u8, # MC 1.21.8,
  })

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

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write effect_id
      buffer.write amplifier
      buffer.write duration
      buffer.write flags
    end.to_slice
  end

  def callback(client)
    entity = client.dimension.entities[entity_id]?
    effect = Rosegold::EntityEffect.new(effect_id, amplifier, duration, flags)

    if client.player.entity_id == entity_id
      if existing_effect = client.player.effects.find { |active_effect| active_effect.effect == effect.effect }
        existing_effect.amplifier = amplifier
        existing_effect.duration = duration
        existing_effect.flags = flags
        return
      end

      client.player.effects << effect
    end

    if entity.nil?
      Log.warn { "Received entity effect packet for unknown entity ID #{entity_id}" }
      return
    end

    if existing_effect = entity.effects.find { |active_effect| active_effect.effect == effect.effect }
      existing_effect.amplifier = amplifier
      existing_effect.duration = duration
      existing_effect.flags = flags
      return
    end

    entity.effects << effect
  end
end
