class Rosegold::Inventory
  property client : Rosegold::Client

  def initialize(@client)
  end

  def slots
    client.current_window.slots
  end

  def main_hand : Slot
    hotbar[client.player.hotbar_selection]
  end

  def off_hand : Slot
    slots[45]
  end

  def equipment : Array(Slot)
    slots[5..8]
  end

  def hotbar : Array(Slot)
    slots[36..44]
  end

  def crafting_input : Array(Slot)
    slots[1..4]
  end

  def crafting_result : Slot
    slots[0]
  end

  # Picks the item with the given id, if it exists in the inventory
  # Returns true if the item was picked, false otherwise
  #
  # Example:
  #   inventory.pick "minecraft:diamond_pickaxe" # => true
  def pick(item_id)
    return true if main_hand.item_id == item_id

    hotbar.each_with_index do |slot, index|
      if slot.item_id == item_id
        client.queue_packet Serverbound::HeldItemChange.new index.to_u8
        client.player.hotbar_selection = index.to_u8
        return true
      end
    end

    slots.each_with_index do |slot, index|
      if slot.item_id == item_id
        client.queue_packet Serverbound::PickItem.new index.to_u16
        return true
      end
    end

    false
  end

  def pick!(item_id)
    pick(item_id) || raise ItemNotFoundError.new("Item #{item_id} not found in inventory")
  end

  class ItemNotFoundError < Exception
  end
end
