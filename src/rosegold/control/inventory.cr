# Utility methods for interacting with the open window.
class Rosegold::Inventory
  property client : Client

  def initialize(@client); end

  forward_missing_to @client.window

  # Picks the item with the given id, if it exists in the inventory
  # Returns true if the item was picked, false otherwise
  #
  # Example:
  #   inventory.pick "minecraft:diamond_pickaxe" # => true
  def pick(item_id)
    return true if main_hand.item_id == item_id

    hotbar.each_with_index do |slot, index|
      if slot.item_id == item_id
        client.send_packet! Serverbound::HeldItemChange.new index.to_u8
        client.player.hotbar_selection = index.to_u8
        return true
      end
    end

    slots.each_with_index do |slot, index|
      if slot.item_id == item_id
        client.send_packet! Serverbound::PickItem.new index.to_u16
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
