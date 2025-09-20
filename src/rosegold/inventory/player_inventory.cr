require "./slot"
require "./slot_offsets"

# Persistent player inventory that matches vanilla Minecraft's model.
# This inventory never changes structure (always 36 slots) and persists across container operations.
class Rosegold::PlayerInventory
  INVENTORY_SIZE      = SlotOffsets::PLAYER_INVENTORY_SIZE
  HOTBAR_SIZE         = SlotOffsets::HOTBAR_SIZE
  MAIN_INVENTORY_SIZE = SlotOffsets::MAIN_INVENTORY_SIZE

  # Persistent inventory items - matches vanilla Player.inventory.items
  @items : Array(Rosegold::Slot)

  def initialize
    # Initialize with empty slots (36 total: 27 main + 9 hotbar)
    @items = Array.new(INVENTORY_SIZE) { Rosegold::Slot.new }
  end

  # Direct access to inventory items (like vanilla)
  def items
    @items
  end

  # Main inventory slots (indices 9-35) - matches vanilla Player.inventory.items
  def main_inventory : Array(Rosegold::Slot)
    @items[HOTBAR_SIZE...INVENTORY_SIZE]
  end

  # Hotbar slots (indices 0-8) - matches vanilla Player.inventory.items
  def hotbar : Array(Rosegold::Slot)
    @items[0...HOTBAR_SIZE]
  end

  # Get slot by index (0-35)
  def [](index : Int32) : Rosegold::Slot
    @items[index]
  end

  # Set slot by index (0-35)
  def []=(index : Int32, slot : Rosegold::Slot)
    @items[index] = slot
  end

  # Update a specific slot (used by packet handlers)
  def update_slot(index : Int32, slot : Rosegold::Slot)
    if index >= 0 && index < INVENTORY_SIZE
      @items[index] = slot
    end
  end

  # Update multiple slots (used by SetContainerContent)
  def update_slots(slots : Array(Rosegold::Slot), start_index : Int32 = 0)
    slots.each_with_index do |slot, i|
      update_slot(start_index + i, slot)
    end
  end

  # Find first empty slot index, returns nil if full
  def first_empty_slot : Int32?
    @items.each_with_index do |slot, index|
      return index if slot.empty?
    end
    nil
  end

  # Count items matching predicate
  def count(&block : Rosegold::Slot -> Bool) : Int32
    @items.count(&block)
  end

  # Find first slot matching predicate
  def find(&block : Rosegold::Slot -> Bool) : Rosegold::Slot?
    @items.find(&block)
  end

  # Get selected hotbar slot (based on client selection)
  def selected_slot(selection : UInt8) : Rosegold::Slot
    clamped_selection = selection.clamp(0_u8, (HOTBAR_SIZE - 1).to_u8)
    hotbar[clamped_selection]
  end

  def to_s(io)
    io.print "PlayerInventory(#{@items.count(&.present?)} items)"
  end
end
