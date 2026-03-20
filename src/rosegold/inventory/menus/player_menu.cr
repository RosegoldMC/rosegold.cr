require "../menu"

# Player inventory menu — the view when no container is open.
# Replaces the previous InventoryMenu class.
# Layout: crafting_result(0), crafting(1-4), armor(5-8), main(9-35), hotbar(36-44), offhand(45)
class Rosegold::PlayerMenu < Rosegold::Menu
  CRAFTING_RESULT =  0
  CRAFTING_START  =  1
  CRAFTING_END    =  4
  ARMOR_START     =  5
  ARMOR_END       =  8
  MAIN_START      =  9
  MAIN_END        = 35
  HOTBAR_START    = 36
  HOTBAR_END      = 44
  OFF_HAND        = 45

  HELMET_SLOT     = 5
  CHESTPLATE_SLOT = 6
  LEGGINGS_SLOT   = 7
  BOOTS_SLOT      = 8

  TOTAL_SLOTS = 46

  @armor_slots : Array(Rosegold::Slot) = Array.new(4) { Rosegold::Slot.new }
  @crafting_slots : Array(Rosegold::Slot) = Array.new(4) { Rosegold::Slot.new }
  @crafting_result : Rosegold::Slot = Rosegold::Slot.new
  @off_hand : Rosegold::Slot = Rosegold::Slot.new

  def initialize(@client)
    @player_inventory = @client.player_inventory
    super(@client, @player_inventory)
  end

  def menu_id : UInt8
    0_u8
  end

  def total_slots : Int32
    TOTAL_SLOTS
  end

  def player_inventory_start : Int32
    MAIN_START
  end

  # --- Slot access ---

  def [](index : Int32) : Rosegold::Slot
    case index
    when CRAFTING_RESULT              then @crafting_result
    when CRAFTING_START..CRAFTING_END then @crafting_slots[index - CRAFTING_START]
    when ARMOR_START..ARMOR_END       then @armor_slots[index - ARMOR_START]
    when MAIN_START..MAIN_END         then @player_inventory[index]
    when HOTBAR_START..HOTBAR_END     then @player_inventory[index - HOTBAR_START]
    when OFF_HAND                     then @off_hand
    else
      raise ArgumentError.new("Invalid slot index #{index} for PlayerMenu")
    end
  end

  def []=(index : Int32, slot : Rosegold::Slot)
    case index
    when CRAFTING_RESULT              then @crafting_result = slot
    when CRAFTING_START..CRAFTING_END then @crafting_slots[index - CRAFTING_START] = slot
    when ARMOR_START..ARMOR_END       then @armor_slots[index - ARMOR_START] = slot
    when MAIN_START..MAIN_END         then @player_inventory[index] = slot
    when HOTBAR_START..HOTBAR_END     then @player_inventory[index - HOTBAR_START] = slot
    when OFF_HAND                     then @off_hand = slot
    else
      raise ArgumentError.new("Invalid slot index #{index} for PlayerMenu")
    end
  end

  # --- Named slot accessors ---

  def crafting_result : Rosegold::Slot
    @crafting_result
  end

  def crafting_grid : Array(Rosegold::Slot)
    @crafting_slots
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

  def armor_slots : Array(Rosegold::Slot)
    @armor_slots
  end

  def crafting_slots : Array(Rosegold::Slot)
    @crafting_slots
  end

  def off_hand : Rosegold::Slot
    @off_hand
  end

  def player_inventory : PlayerInventory
    @player_inventory
  end

  # --- Slot group accessors ---

  def offhand_slot_index : Int32
    OFF_HAND
  end

  def hotbar_slot_index(hotbar_nr : Int32) : Int32
    HOTBAR_START + hotbar_nr
  end

  def container_slots : Array(Rosegold::WindowSlot)
    Array(Rosegold::WindowSlot).new(0)
  end

  def inventory_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(27)
    @player_inventory.main_inventory.each_with_index do |slot, index|
      result << Rosegold::WindowSlot.new(MAIN_START + index, slot)
    end
    result
  end

  def hotbar_window_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(9)
    @player_inventory.hotbar.each_with_index do |slot, index|
      result << Rosegold::WindowSlot.new(HOTBAR_START + index, slot)
    end
    result
  end

  def offhand : Array(Rosegold::WindowSlot)
    [Rosegold::WindowSlot.new(OFF_HAND, self[OFF_HAND])]
  end

  # --- Validation ---

  def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    return false if item_slot.empty?
    case slot_index
    when CRAFTING_RESULT then false
    when HELMET_SLOT     then ItemConstants.helmet?(item_slot.item_id_int)
    when CHESTPLATE_SLOT then ItemConstants.chestplate?(item_slot.item_id_int)
    when LEGGINGS_SLOT   then ItemConstants.leggings?(item_slot.item_id_int)
    when BOOTS_SLOT      then ItemConstants.boots?(item_slot.item_id_int)
    when OFF_HAND        then true
    else                      true
    end
  end

  def may_pickup?(slot_index : Int32) : Bool
    true
  end

  def allow_modification?(slot_index : Int32) : Bool
    current_item = self[slot_index]
    return true if current_item.empty?
    may_pickup?(slot_index) && may_place?(slot_index, current_item)
  end

  def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    case slot_index
    when ARMOR_START..ARMOR_END then 1
    else                             get_max_stack_size(item_slot)
    end
  end

  # --- Shift-click (quickMoveStack from InventoryMenu.java) ---

  def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original_item = copy_slot(slot)

    case slot_index
    when 0 # Crafting result
      if !move_item_stack_to(slot_index, 9, 45, true)
        return Rosegold::Slot.new
      end
      handle_crafting_result_quick_craft(original_item, self[slot_index])
    when 1..4 # Crafting grid
      if !move_item_stack_to(slot_index, 9, 45, false)
        return Rosegold::Slot.new
      end
    when 5..8 # Armor
      if !move_item_stack_to(slot_index, 9, 45, false)
        return Rosegold::Slot.new
      end
    else # Inventory + hotbar (9-45)
      equipment_slot = get_equipment_slot_for_item(slot)

      if equipment_slot && armor_slot?(equipment_slot) && self[equipment_slot].empty?
        if !move_item_stack_to(slot_index, equipment_slot, equipment_slot + 1, false)
          return Rosegold::Slot.new
        end
      elsif offhand_item?(slot) && self[45].empty?
        if !move_item_stack_to(slot_index, 45, 46, false)
          return Rosegold::Slot.new
        end
      elsif slot_index >= 9 && slot_index < 36
        if !move_item_stack_to(slot_index, 36, 45, false)
          return Rosegold::Slot.new
        end
      elsif slot_index >= 36 && slot_index < 45
        if !move_item_stack_to(slot_index, 9, 36, false)
          return Rosegold::Slot.new
        end
      else
        if !move_item_stack_to(slot_index, 9, 45, false)
          return Rosegold::Slot.new
        end
      end
    end

    if self[slot_index].empty?
      self[slot_index] = Rosegold::Slot.new
    end

    return Rosegold::Slot.new if self[slot_index].count == original_item.count
    original_item
  end

  # --- Close ---

  def close
    # Player inventory can't be closed
  end

  def handle_close
    # Player inventory can't be closed
  end

  # --- Private helpers ---

  private def get_equipment_slot_for_item(item_slot : Rosegold::Slot) : Int32?
    return nil if item_slot.empty?
    return HELMET_SLOT if ItemConstants.helmet?(item_slot.item_id_int)
    return CHESTPLATE_SLOT if ItemConstants.chestplate?(item_slot.item_id_int)
    return LEGGINGS_SLOT if ItemConstants.leggings?(item_slot.item_id_int)
    return BOOTS_SLOT if ItemConstants.boots?(item_slot.item_id_int)
    nil
  end

  private def armor_slot?(slot_index : Int32) : Bool
    slot_index >= 5 && slot_index <= 8
  end

  private def offhand_item?(item_slot : Rosegold::Slot) : Bool
    return false if item_slot.empty?
    ItemConstants.offhand_item?(item_slot.item_id_int)
  end

  private def handle_crafting_result_quick_craft(original_slot : Rosegold::Slot, current_slot : Rosegold::Slot)
    items_moved = original_slot.count.to_i - current_slot.count.to_i
    if items_moved > 0
      # Vanilla triggers achievement checks here — no-op for us
    end
  end
end
