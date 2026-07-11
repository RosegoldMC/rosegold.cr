require "../packet"
require "../../world/entity_metadata"

class Rosegold::Clientbound::SetEntityData < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x5C_u32, # MC 1.21.8
    773_u32 => 0x61_u32, # MC 1.21.9
    774_u32 => 0x61_u32, # MC 1.21.11
    775_u32 => 0x63_u32, # MC 26.1
    776_u32 => 0x63_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  VARINT_SERIALIZERS = {
    :varint, :direction, :pose, :opt_varint,
    :block_state, :opt_block_state, :cat_variant, :cat_sound_variant, :cow_variant,
  }

  record Entry, index : UInt8, serializer_id : UInt32, value : Rosegold::Entity::TrackedValue

  property entity_id : UInt64
  property entries : Array(Entry)

  def initialize(@entity_id, @entries); end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u64
    entries = [] of Entry
    loop do
      index = packet.read_byte
      break if index == 0xFF_u8
      serializer_id = packet.read_var_int
      symbol = Rosegold::EntityMetadata.serializer_for(serializer_id, Client.protocol_version)
      raise "Unknown entity metadata serializer #{serializer_id} for protocol #{Client.protocol_version}" if symbol.nil?
      entries << Entry.new(index, serializer_id, read_value(packet, symbol))
    end
    new(entity_id, entries)
  end

  private def self.read_value(io, symbol : Symbol) : Rosegold::Entity::TrackedValue
    case symbol
    when :byte               then io.read_byte
    when :long               then io.read_var_long
    when :float              then io.read_float
    when :string             then io.read_var_string
    when :boolean            then io.read_bool
    when :text_component     then io.read_text_component
    when :opt_text_component then io.read_bool ? io.read_text_component : nil
    when :slot               then Rosegold::Slot.read(io)
    when :rotations          then {io.read_float, io.read_float, io.read_float}
    when :block_pos          then io.read_bit_location
    when :opt_block_pos      then io.read_bool ? io.read_bit_location : nil
    when :opt_uuid           then io.read_bool ? io.read_uuid : nil
    when :nbt                then io.read_nbt_unamed
    when :villager_data      then [io.read_var_int, io.read_var_int, io.read_var_int]
    when :particle, :particles
      raise "Entity metadata serializer #{symbol} has no stream codec; cannot advance IO"
    else
      raise "Unhandled entity metadata serializer #{symbol}" unless VARINT_SERIALIZERS.includes?(symbol)
      io.read_var_int
    end
  end

  def values : Hash(UInt8, Rosegold::Entity::TrackedValue)
    result = Hash(UInt8, Rosegold::Entity::TrackedValue).new
    entries.each { |entry| result[entry.index] = entry.value }
    result
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      entries.each do |entry|
        buffer.write_byte entry.index
        buffer.write entry.serializer_id
        write_value(buffer, entry.serializer_id, entry.value)
      end
      buffer.write_byte 0xFF_u8
    end.to_slice
  end

  private def write_value(io, serializer_id : UInt32, value : Rosegold::Entity::TrackedValue) : Nil
    symbol = Rosegold::EntityMetadata.serializer_for(serializer_id, Client.protocol_version)
    case symbol
    when :byte           then io.write_byte value.as(UInt8)
    when :long           then io.write value.as(UInt64)
    when :float          then io.write_full value.as(Float32)
    when :string         then io.write value.as(String)
    when :boolean        then io.write value.as(Bool)
    when :text_component then io.write value.as(Rosegold::TextComponent)
    when :opt_text_component
      write_optional(io, value) { |present| io.write present.as(Rosegold::TextComponent) }
    when :slot then io.write value.as(Rosegold::Slot)
    when :rotations
      rotation = value.as(Tuple(Float32, Float32, Float32))
      io.write_full rotation[0]
      io.write_full rotation[1]
      io.write_full rotation[2]
    when :block_pos then io.write value.as(Rosegold::Vec3i)
    when :opt_block_pos
      write_optional(io, value) { |present| io.write present.as(Rosegold::Vec3i) }
    when :opt_uuid
      write_optional(io, value) { |present| io.write present.as(UUID) }
    when :nbt
      tag = value.as(Minecraft::NBT::Tag)
      io.write_byte tag.tag_type
      tag.write io
    when :villager_data
      value.as(Array(UInt32)).each { |element| io.write element }
    else
      raise "Unhandled entity metadata serializer #{symbol}" unless VARINT_SERIALIZERS.includes?(symbol)
      io.write value.as(UInt32)
    end
  end

  private def write_optional(io, value : Rosegold::Entity::TrackedValue, &)
    if present = value
      io.write true
      yield present
    else
      io.write false
    end
  end

  def callback(client)
    if entity = client.dimension.entities[entity_id]?
      entity.tracked_data.merge!(values)
    end
  end
end
