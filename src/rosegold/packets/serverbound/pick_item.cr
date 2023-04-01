require "../packet"

# Swap out an empty space on the hotbar with the item in the given inventory slot.
# The server selects an empty slot, swaps the items, and then sends 3 packets:
# - SetSlot for server selected slot
# - SetSlot for requested slot_nr
# - HeldItemChange for server selected slot
class Rosegold::Serverbound::PickItem < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x17_u8

  property slot_nr : UInt16

  def initialize(@slot_nr : UInt16); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write slot_nr
    end.to_slice
  end
end
