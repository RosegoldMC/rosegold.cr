require "../../world/look"
require "../../world/slot"
require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::EntityEquipment < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x5F_u8, # MC 1.21.8,
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
