require "../packet"

class Rosegold::Clientbound::UpdateAttributes < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x7C_u32, # MC 1.21.8
    773_u32 => 0x81_u32, # MC 1.21.9
    774_u32 => 0x81_u32, # MC 1.21.11
    775_u32 => 0x83_u32, # MC 26.1
    776_u32 => 0x83_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  property entity_id : UInt64
  property attribute_snapshots : Array(Rosegold::AttributeSnapshot)

  def initialize(@entity_id, @attribute_snapshots)
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    count = packet.read_var_int
    snapshots = Array(Rosegold::AttributeSnapshot).new(count) do
      attribute_id = packet.read_var_int
      base = packet.read_double
      modifier_count = packet.read_var_int
      modifiers = Array(Rosegold::AttributeModifier).new(modifier_count) do
        id = packet.read_var_string
        amount = packet.read_double
        operation = packet.read_var_int.to_u8
        Rosegold::AttributeModifier.new(id, amount, operation)
      end
      Rosegold::AttributeSnapshot.new(attribute_id, base, modifiers)
    end
    self.new(entity_id, snapshots)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      buffer.write attribute_snapshots.size.to_u32
      attribute_snapshots.each do |snapshot|
        buffer.write snapshot.attribute_id
        buffer.write_full snapshot.base
        buffer.write snapshot.modifiers.size.to_u32
        snapshot.modifiers.each do |modifier|
          buffer.write modifier.id
          buffer.write_full modifier.amount
          buffer.write modifier.operation.to_u32
        end
      end
    end.to_slice
  end

  def callback(client)
    if entity = client.dimension.entities[entity_id]?
      entity.apply_attribute_snapshots(attribute_snapshots)
    end
    if entity_id == client.player.entity_id
      client.player.apply_attribute_snapshots(attribute_snapshots)
    end
  end
end
