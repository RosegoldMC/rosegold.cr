require "../../world/look"
require "../../world/slot"
require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::EntityEquipment < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x50_u8

  property \
    entity_id : Int32,
    main_hand : Slot? = nil,
    off_hand : Slot? = nil,
    boots : Slot? = nil,
    leggings : Slot? = nil,
    chestplate : Slot? = nil,
    helmet : Slot? = nil

  def initialize(@entity_id); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      array = [main_hand, off_hand, boots, leggings, chestplate, helmet]
      array.each_with_index do |slot, i|
        next unless slot && slot.present?
        i = i.to_u8
        i |= 0x80 unless i == 5
        buffer.write i
        slot.write buffer
      end
    end.to_slice
  end
end
