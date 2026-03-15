class Rosegold::Clientbound::DestroyEntities < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x46_u32, # MC 1.21.8
    774_u32 => 0x4B_u32, # MC 1.21.11
  })
  class_getter state = Rosegold::ProtocolState::PLAY

  property entity_ids : Array(UInt64)

  def initialize(@entity_ids)
  end

  def self.read(packet)
    entity_ids = [] of UInt64
    count = packet.read_var_int
    if Client.protocol_version >= 774_u32
      count.times { entity_ids << packet.read_var_int.to_u64 }
    else
      count.times { entity_ids << packet.read_var_long }
    end
    self.new entity_ids
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_ids.size
      if Client.protocol_version >= 774_u32
        entity_ids.each { |entity_id| buffer.write entity_id.to_u32 }
      else
        entity_ids.each { |entity_id| buffer.write entity_id }
      end
    end.to_slice
  end

  def callback(client)
    entity_ids.each { |entity_id| client.dimension.entities.delete(entity_id) }
  end
end
