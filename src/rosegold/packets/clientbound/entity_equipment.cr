require "../../world/look"
require "../../inventory/slot"
require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::EntityEquipment < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x5F_u32, # MC 1.21.8
    774_u32 => 0x64_u32, # MC 1.21.11
    775_u32 => 0x66_u32, # MC 26.1
  })

  property \
    entity_id : Int32,
    main_hand : Slot? = nil,
    off_hand : Slot? = nil,
    boots : Slot? = nil,
    leggings : Slot? = nil,
    chestplate : Slot? = nil,
    helmet : Slot? = nil

  def initialize(@entity_id); end

  def self.read(packet)
    entity_id = packet.read_var_int.to_i32
    equipment = self.new(entity_id)
    loop do
      raw_slot = packet.read_byte
      slot_index = raw_slot & 0x7F
      has_next = (raw_slot & 0x80) != 0
      begin
        item = Slot.read(packet)
      rescue ex : UnknownComponentError
        Log.warn { "#{ex.message} in EntityEquipment (entity #{entity_id}, slot #{slot_index})" }
        item = Slot.new
      end
      case slot_index
      when 0 then equipment.main_hand = item
      when 1 then equipment.off_hand = item
      when 2 then equipment.boots = item
      when 3 then equipment.leggings = item
      when 4 then equipment.chestplate = item
      when 5 then equipment.helmet = item
      else        Log.debug { "Ignoring equipment slot #{slot_index} for entity #{entity_id}" }
      end
      break unless has_next
    end
    equipment
  end

  def valid?
    slots = [main_hand, off_hand, boots, leggings, chestplate, helmet]
      .select &.try &.present?
    !slots.empty?
  end

  def write : Bytes
    slots = [main_hand, off_hand, boots, leggings, chestplate, helmet]
      .map_with_index { |slot, i| {slot, i.to_u8} }
      .select { |slot, _| slot && slot.present? }
    raise "Cannot write empty EntityEquipment" if slots.empty?
    _, last_i = slots.last
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      slots.each do |slot, i|
        i |= 0x80 unless i == last_i
        buffer.write i
        buffer.write slot.not_nil! # ameba:disable Lint/NotNil
      end
    end.to_slice
  end
end
