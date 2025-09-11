# Constants for Minecraft item IDs and game data
# Based on Minecraft 1.21.8 protocol via MCData
module Rosegold::ItemConstants
  # Helper to check if item has specific enchantment category
  private def self.has_enchant_category?(item_id : UInt32, category : String) : Bool
    found_item = MCData::DEFAULT.items.find { |item| item.id == item_id }
    return false unless found_item
    enchant_categories = found_item.enchant_categories
    return false unless enchant_categories
    enchant_categories.includes?(category)
  end

  # Container types
  module ContainerType
    GENERIC_9X1 = 0_u32 # Dispenser, dropper
    GENERIC_9X2 = 1_u32
    GENERIC_9X3 = 2_u32 # Chest, barrel
    GENERIC_9X4 = 3_u32
    GENERIC_9X5 = 4_u32
    GENERIC_9X6 = 5_u32 # Large chest
    GENERIC_3X3 = 6_u32 # Crafting table, etc.

    # Expected sizes for validation
    EXPECTED_SIZES = {
      GENERIC_9X1 => 9,
      GENERIC_9X2 => 18,
      GENERIC_9X3 => 27,
      GENERIC_9X4 => 36,
      GENERIC_9X5 => 45,
      GENERIC_9X6 => 54,
      GENERIC_3X3 => 9,
    }
  end

  # Player inventory slot indices
  module PlayerSlots
    # Player inventory menu layout (46 slots total)
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

    # Specific armor slots
    HELMET_SLOT     = 5
    CHESTPLATE_SLOT = 6
    LEGGINGS_SLOT   = 7
    BOOTS_SLOT      = 8

    TOTAL_SLOTS = 46
  end

  # Standard inventory sizes
  module InventorySize
    PLAYER_INVENTORY = 36 # Main inventory (27) + hotbar (9)
    CRAFTING_GRID    =  4 # 2x2 crafting
    ARMOR_SLOTS      =  4 # Helmet, chestplate, leggings, boots
    MAX_STACK_SIZE   = 64
  end

  # Quickcraft types
  module Quickcraft
    CHARITABLE = 0 # Distribute evenly
    GREEDY     = 1 # 1 per slot
    CLONE      = 2 # Fill stacks (creative mode)

    # Quickcraft status
    START    = 0
    CONTINUE = 1
    END      = 2
  end

  # Helper methods - accept both Int32 and UInt32 for compatibility
  def self.helmet?(item_id : Int32 | UInt32) : Bool
    has_enchant_category?(item_id.to_u32, "head_armor")
  end

  def self.chestplate?(item_id : Int32 | UInt32) : Bool
    has_enchant_category?(item_id.to_u32, "chest_armor")
  end

  def self.leggings?(item_id : Int32 | UInt32) : Bool
    has_enchant_category?(item_id.to_u32, "leg_armor")
  end

  def self.boots?(item_id : Int32 | UInt32) : Bool
    has_enchant_category?(item_id.to_u32, "foot_armor")
  end

  def self.armor?(item_id : Int32 | UInt32) : Bool
    helmet?(item_id) || chestplate?(item_id) || leggings?(item_id) || boots?(item_id)
  end

  def self.offhand_item?(item_id : Int32 | UInt32) : Bool
    found_item = MCData::DEFAULT.items.find { |item| item.id == item_id.to_u32 }
    return false unless found_item
    found_item.name == "shield"
  end

  def self.get_equipment_slot_for_item(item_id : Int32 | UInt32) : Int32?
    return PlayerSlots::HELMET_SLOT if helmet?(item_id)
    return PlayerSlots::CHESTPLATE_SLOT if chestplate?(item_id)
    return PlayerSlots::LEGGINGS_SLOT if leggings?(item_id)
    return PlayerSlots::BOOTS_SLOT if boots?(item_id)
    nil
  end

  def self.expected_container_size(type_id : UInt32) : Int32?
    ContainerType::EXPECTED_SIZES[type_id]?
  end
end
