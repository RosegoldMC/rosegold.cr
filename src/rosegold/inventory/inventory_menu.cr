require "./slot"
require "./player_inventory"
require "./remote_slot"
require "./inventory_operations"
require "./item_constants"
require "../models/chat"

# Player inventory menu - the view when no container is open.
# This is equivalent to vanilla's InventoryMenu.
class Rosegold::InventoryMenu
  include InventoryOperations
  @client : Client

  # Fixed properties for player inventory menu
  getter id : UInt8 = 0_u8
  getter title : Chat = Chat.new("Player Inventory")
  getter type_id : UInt32 = 0_u32
  property state_id : UInt32 = 0

  # Reference to persistent player inventory
  @player_inventory : PlayerInventory

  # Cursor slot (what player is carrying)
  @cursor : Rosegold::Slot = Rosegold::Slot.new

  # Additional player inventory slots (armor, crafting, etc.)
  @armor_slots : Array(Rosegold::Slot) = Array.new(4) { Rosegold::Slot.new }    # helmet, chestplate, leggings, boots
  @crafting_slots : Array(Rosegold::Slot) = Array.new(4) { Rosegold::Slot.new } # 2x2 crafting grid
  @crafting_result : Rosegold::Slot = Rosegold::Slot.new                        # crafting result
  @off_hand : Rosegold::Slot = Rosegold::Slot.new                               # shield slot

  # Remote slot tracking (what server thinks slots should contain)
  @remote_slots : Array(RemoteSlot)
  @remote_cursor : RemoteSlot = RemoteSlot.new

  def initialize(@client)
    @player_inventory = @client.player_inventory
    @remote_slots = Array.new(TOTAL_SLOTS) { RemoteSlot.new }
  end

  # Total slots: crafting result(1) + crafting(4) + armor(4) + main inventory(27) + hotbar(9) + off hand(1) = 46
  TOTAL_SLOTS = ItemConstants::PlayerSlots::TOTAL_SLOTS

  # Get slot by absolute index (following vanilla player inventory layout)
  def [](index : Int32) : Rosegold::Slot
    case index
    when ItemConstants::PlayerSlots::CRAFTING_RESULT
      @crafting_result
    when ItemConstants::PlayerSlots::CRAFTING_START..ItemConstants::PlayerSlots::CRAFTING_END
      @crafting_slots[index - ItemConstants::PlayerSlots::CRAFTING_START]
    when ItemConstants::PlayerSlots::ARMOR_START..ItemConstants::PlayerSlots::ARMOR_END
      @armor_slots[index - ItemConstants::PlayerSlots::ARMOR_START]
    when ItemConstants::PlayerSlots::MAIN_START..ItemConstants::PlayerSlots::MAIN_END
      @player_inventory[index] # Main inventory (same indices as persistent inventory)
    when ItemConstants::PlayerSlots::HOTBAR_START..ItemConstants::PlayerSlots::HOTBAR_END
      @player_inventory[index - ItemConstants::PlayerSlots::HOTBAR_START] # Hotbar (maps to persistent inventory indices 0-8)
    when ItemConstants::PlayerSlots::OFF_HAND
      @off_hand
    else
      raise ArgumentError.new("Invalid slot index #{index} for player inventory menu")
    end
  end

  # Set slot by absolute index
  def []=(index : Int32, slot : Rosegold::Slot)
    case index
    when ItemConstants::PlayerSlots::CRAFTING_RESULT
      @crafting_result = slot
    when ItemConstants::PlayerSlots::CRAFTING_START..ItemConstants::PlayerSlots::CRAFTING_END
      @crafting_slots[index - ItemConstants::PlayerSlots::CRAFTING_START] = slot
    when ItemConstants::PlayerSlots::ARMOR_START..ItemConstants::PlayerSlots::ARMOR_END
      @armor_slots[index - ItemConstants::PlayerSlots::ARMOR_START] = slot
    when ItemConstants::PlayerSlots::MAIN_START..ItemConstants::PlayerSlots::MAIN_END
      @player_inventory[index] = slot # Update persistent inventory
    when ItemConstants::PlayerSlots::HOTBAR_START..ItemConstants::PlayerSlots::HOTBAR_END
      @player_inventory[index - ItemConstants::PlayerSlots::HOTBAR_START] = slot # Update persistent inventory hotbar
    when ItemConstants::PlayerSlots::OFF_HAND
      @off_hand = slot
    else
      raise ArgumentError.new("Invalid slot index #{index} for player inventory menu")
    end
  end

  # Direct access to persistent player inventory
  def player_inventory : PlayerInventory
    @player_inventory
  end

  # Player inventory slots (all 36 slots for compatibility)
  def player_inventory_slots : Array(Rosegold::Slot)
    @player_inventory.items
  end

  # Armor slots
  def armor_slots : Array(Rosegold::Slot)
    @armor_slots
  end

  def helmet : Rosegold::Slot
    @armor_slots[0]
  end

  def chestplate : Rosegold::Slot
    @armor_slots[1]
  end

  def leggings : Rosegold::Slot
    @armor_slots[2]
  end

  def boots : Rosegold::Slot
    @armor_slots[3]
  end

  # Crafting slots
  def crafting_slots : Array(Rosegold::Slot)
    @crafting_slots
  end

  def crafting_result : Rosegold::Slot
    @crafting_result
  end

  # Off-hand slot
  def off_hand : Rosegold::Slot
    @off_hand
  end

  # Abstract methods required by InventoryOperations
  def menu_id : UInt8
    0_u8
  end

  def total_slots : Int32
    TOTAL_SLOTS
  end

  # Vanilla-compatible slot validation for player inventory
  private def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    return false if item_slot.empty?

    # Player inventory slots have specific rules:
    case slot_index
    when ItemConstants::PlayerSlots::CRAFTING_RESULT
      false # Can't place items in crafting result
    when ItemConstants::PlayerSlots::HELMET_SLOT
      ItemConstants.helmet?(item_slot.item_id_int)
    when ItemConstants::PlayerSlots::CHESTPLATE_SLOT
      ItemConstants.chestplate?(item_slot.item_id_int)
    when ItemConstants::PlayerSlots::LEGGINGS_SLOT
      ItemConstants.leggings?(item_slot.item_id_int)
    when ItemConstants::PlayerSlots::BOOTS_SLOT
      ItemConstants.boots?(item_slot.item_id_int)
    when ItemConstants::PlayerSlots::OFF_HAND
      true # Off-hand can hold many item types
    else   # Regular inventory, hotbar
      true
    end
  end

  private def may_pickup?(slot_index : Int32) : Bool
    # Player inventory generally allows all pickups
    true
  end

  # Check if player can modify this slot (vanilla's allowModification logic)
  private def allow_modification?(slot_index : Int32) : Bool
    current_item = self[slot_index]
    may_pickup?(slot_index) && may_place?(slot_index, current_item)
  end

  private def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    get_max_stack_size(item_slot)
  end

  # Abstract method implementations for InventoryOperations
  def offhand_slot_index : Int32
    45
  end

  def hotbar_slot_index(hotbar_nr : Int32) : Int32
    36 + hotbar_nr
  end

  def content_slots : Array(Rosegold::WindowSlot)
    Array(Rosegold::WindowSlot).new(0)
  end

  def inventory_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(27)
    main_inventory_slots.each_with_index do |slot, index|
      result << Rosegold::WindowSlot.new(9 + index, slot)
    end
    result
  end

  def hotbar_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(9)
    @player_inventory.hotbar.each_with_index do |slot, index|
      result << Rosegold::WindowSlot.new(36 + index, slot)
    end
    result
  end

  # Player offhand slot for compatibility
  def offhand : Array(Rosegold::WindowSlot)
    [Rosegold::WindowSlot.new(45, self[45])]
  end

  # Close container (no-op for player inventory)
  def close
    # Player inventory can't be closed, no-op
  end

  # Handle close (no-op for player inventory)
  def handle_close
    # Player inventory can't be closed, no-op
  end

  # Vanilla's quickMoveStack equivalent - complete implementation from InventoryMenu.java lines 91-150
  private def perform_shift_click(slot_index : Int32)
    return if slot_index < 0 || slot_index >= TOTAL_SLOTS
    return if self[slot_index].empty?

    source_slot = self[slot_index]
    original_slot = copy_slot(source_slot)

    # Handle each slot range with vanilla's exact logic
    case slot_index
    when 0 # Crafting result (slot 0)
      # Move to inventory slots 9-45 with reverse=true (vanilla behavior)
      if !move_item_stack_to(slot_index, 9, 45, true)
        return
      end
      # Trigger crafting result callback (equivalent to var4.onQuickCraft in vanilla)
      handle_crafting_result_quick_craft(original_slot, source_slot)
    when 1..4 # Crafting grid (slots 1-4)
      # Move to inventory slots 9-45
      if !move_item_stack_to(slot_index, 9, 45, false)
        return
      end
    when 5..8 # Armor slots (slots 5-8)
      # Move to inventory slots 9-45
      if !move_item_stack_to(slot_index, 9, 45, false)
        return
      end
    else # Inventory and hotbar slots (slots 9-45)
      # Check for equipment auto-targeting first (vanilla's complex equipment logic)
      equipment_slot = get_equipment_slot_for_item(source_slot)

      # Try armor slot targeting (vanilla lines 112-116)
      if equipment_slot && armor_slot?(equipment_slot) && self[equipment_slot].empty?
        if !move_item_stack_to(slot_index, equipment_slot, equipment_slot + 1, false)
          return
        end
        # Try off-hand targeting (vanilla lines 117-120)
      elsif offhand_item?(source_slot) && self[45].empty?
        if !move_item_stack_to(slot_index, 45, 46, false)
          return
        end
        # Main inventory to hotbar (vanilla lines 121-124)
      elsif slot_index >= 9 && slot_index < 36
        if !move_item_stack_to(slot_index, 36, 45, false)
          return
        end
        # Hotbar to main inventory (vanilla lines 125-128)
      elsif slot_index >= 36 && slot_index < 45
        if !move_item_stack_to(slot_index, 9, 36, false)
          return
        end
        # Fallback: try inventory slots 9-45 (vanilla line 129)
      else
        if !move_item_stack_to(slot_index, 9, 45, false)
          return
        end
      end
    end

    # Update slot state after move (vanilla behavior)
    if self[slot_index].empty?
      self[slot_index] = Rosegold::Slot.new
    end
  end

  # Equipment slot mapping for auto-targeting (vanilla's getEquipmentSlotForItem logic)
  private def get_equipment_slot_for_item(item_slot : Rosegold::Slot) : Int32?
    return nil if item_slot.empty?

    # Use ItemConstants methods instead of hardcoded IDs
    return ItemConstants::PlayerSlots::HELMET_SLOT if ItemConstants.helmet?(item_slot.item_id_int)
    return ItemConstants::PlayerSlots::CHESTPLATE_SLOT if ItemConstants.chestplate?(item_slot.item_id_int)
    return ItemConstants::PlayerSlots::LEGGINGS_SLOT if ItemConstants.leggings?(item_slot.item_id_int)
    return ItemConstants::PlayerSlots::BOOTS_SLOT if ItemConstants.boots?(item_slot.item_id_int)

    nil
  end

  private def armor_slot?(slot_index : Int32) : Bool
    slot_index >= 5 && slot_index <= 8
  end

  private def offhand_item?(item_slot : Rosegold::Slot) : Bool
    return false if item_slot.empty?

    # Use ItemConstants method instead of hardcoded IDs
    ItemConstants.offhand_item?(item_slot.item_id_int)
  end

  # Handle crafting result quick craft callback (vanilla's onQuickCraft)
  private def handle_crafting_result_quick_craft(original_slot : Rosegold::Slot, current_slot : Rosegold::Slot)
    # Calculate how many items were moved
    items_moved = original_slot.count.to_i - current_slot.count.to_i
    if items_moved > 0
      # In vanilla, this triggers achievement/advancement checks
      # For now, this is a no-op placeholder
    end
  end
end
