require "./slot"

# Remote slot tracking - follows vanilla's approach
# This tracks what the server thinks each slot should contain
class Rosegold::RemoteSlot
  getter slot : Rosegold::Slot

  def initialize(@slot = Rosegold::Slot.new)
  end

  # Check if remote slot matches current local slot
  def matches?(local_slot : Rosegold::Slot) : Bool
    return true if @slot.empty? && local_slot.empty?
    return false if @slot.empty? != local_slot.empty?

    @slot.item_id_int == local_slot.item_id_int &&
      @slot.count == local_slot.count &&
      @slot.components_to_add == local_slot.components_to_add &&
      @slot.components_to_remove == local_slot.components_to_remove
  end

  # Force update remote slot (when server sends updates)
  def force(slot : Slot)
    @slot = slot
  end
end
