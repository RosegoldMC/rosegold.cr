# Utility methods for interacting with the open window.
class Rosegold::Inventory
  private property client : Client

  def initialize(@client); end

  forward_missing_to @client.window

  # Picks a matching slot, if it exists in the inventory.
  # Returns true if the item was picked, false otherwise.
  #
  # Example:
  #   inventory.pick "diamond_pickaxe" # => true
  #   inventory.pick &.empty? # => true
  #   inventory.pick { |slot| slot.item_id == "diamond_pickaxe" && slot.efficiency >= 4 } # => false
  def pick(spec)
    return true if main_hand.matches? spec

    hotbar.each_with_index do |slot, index|
      if slot.matches? spec
        client.send_packet! Serverbound::HeldItemChange.new index.to_u8
        client.player.hotbar_selection = index.to_u8
        return true
      end
    end

    slots.each do |slot|
      if slot.matches? spec
        client.send_packet! Serverbound::PickItem.new slot.slot_nr.to_u16
        sleep 1 # TODO wait for server to finish updating slot and hotbar_index
        return true
      end
    end

    false
  end

  def pick!(spec)
    pick(spec) || raise ItemNotFoundError.new("Item #{item_id} not found in inventory")
  end

  class ItemNotFoundError < Exception
  end
end
