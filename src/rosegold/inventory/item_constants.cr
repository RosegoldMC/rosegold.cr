# Constants for Minecraft item IDs and game data
# Based on Minecraft 1.21.8 protocol via MCData
module Rosegold::ItemConstants
  # Helper to check if item has specific enchantment category
  private def self.has_enchant_category?(item_id : UInt32, category : String) : Bool
    found_item = MCData.default.items.find { |item| item.id == item_id }
    return false unless found_item
    enchant_categories = found_item.enchant_categories
    return false unless enchant_categories
    enchant_categories.includes?(category)
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

  def self.lapis_lazuli?(item_id : Int32 | UInt32) : Bool
    found_item = MCData.default.items.find { |item| item.id == item_id.to_u32 }
    return false unless found_item
    found_item.name == "lapis_lazuli"
  end

  def self.offhand_item?(item_id : Int32 | UInt32) : Bool
    found_item = MCData.default.items.find { |item| item.id == item_id.to_u32 }
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
end
