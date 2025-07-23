class Rosegold::Clientbound::DestroyEntities < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x3A_u8, # MC 1.18
    767_u32 => 0x3A_u8, # MC 1.21
    769_u32 => 0x3A_u8, # MC 1.21.4,
    771_u32 => 0x3A_u8, # MC 1.21.6,
    772_u32 => 0x46_u8, # MC 1.21.8,
  })
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
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_ids.size
      entity_ids.each { |entity_id| buffer.write entity_id }
    end.to_slice
  end

  def callback(client)
    entity_ids.each { |entity_id| client.dimension.entities.delete(entity_id) }
  end
end
