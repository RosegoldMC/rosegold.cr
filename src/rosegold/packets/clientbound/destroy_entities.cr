class Rosegold::Clientbound::DestroyEntities < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x3A_u8
  class_getter state = Rosegold::ProtocolState::PLAY

  property entity_ids : Array(UInt64)

  def initialize(@entity_ids)
  end

  def self.read(packet)
    entity_ids = [] of UInt64
    count = packet.read_var_int
    count.times { entity_ids << packet.read_var_long }
    self.new entity_ids
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_ids.size
      entity_ids.each { |entity_id| buffer.write entity_id }
    end.to_slice
  end

  def callback(client)
    entity_ids.each { |entity_id| client.dimension.entities.delete(entity_id) }
  end
end
