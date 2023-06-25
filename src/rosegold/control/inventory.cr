# Utility methods for interacting with the open window.
class Rosegold::Inventory
  private property client : Client

  def initialize(@client); end

  forward_missing_to @client.window

  # Returns the number of matching items in the entire window, or in the given slots range.
  #
  # Example:
  #   inventory.count "diamond_pickaxe" # => 2
  #   inventory.count &.empty? # => 2
  #   inventory.count { |slot| slot.item_id == "diamond_pickaxe" && slot.efficiency >= 4 } # => 1
  #   inventory.count &.empty?, hotbar # => 1
  def count(spec, slots = slots)
    slots.select(&.matches? spec).sum(&.count)
  end

  def count(&spec : WindowSlot -> _)
    count(spec)
  end

  # Picks a matching slot, if it exists in the inventory.
  # Returns true if the item was picked, false otherwise.
  #
  # Example:
  #   inventory.pick "diamond_pickaxe" # => true
  #   inventory.pick &.empty? # => true
  #   inventory.pick { |slot| slot.item_id == "diamond_pickaxe" && slot.efficiency >= 4 } # => false
  def pick(spec)
    return true if main_hand.matches?(spec) && !main_hand.needs_repair?

    hotbar.each_with_index do |slot, index|
      if slot.matches?(spec) && !slot.needs_repair?
        client.send_packet! Serverbound::HeldItemChange.new index.to_u8
        client.player.hotbar_selection = index.to_u8
        return true
      end
    end

    slots.each do |slot|
      if slot.matches?(spec) && !slot.needs_repair?
        swap_hotbar client.player.hotbar_selection, slot
        return true
      end
    end

    false
  end

  def pick!(spec)
    pick(spec) || raise ItemNotFoundError.new("Item #{spec} not found in inventory")
  end

  # Tries to transfer at least `count` matching items from the player inventory to the container, using shift-clicking.
  # Returns the number of actually transferred items.
  #
  # Example:
  #   inventory.withdraw_at_least 5, "diamond_pickaxe" # => 3
  #   inventory.withdraw_at_least 5, &.empty?, hotbar # => 1
  #   inventory.withdraw_at_least 5, { |slot| slot.item_id == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def withdraw_at_least(count, spec, source : Array(WindowSlot) = content, target : Array(WindowSlot) = inventory + hotbar)
    shift_click_at_least count, spec, source
  end

  def withdraw_at_least(count, &spec : WindowSlot -> _)
    withdraw_at_least(count, spec)
  end

  # Tries to transfer at least `count` matching items from the container to the player inventory, using shift-clicking.
  # Returns the number of actually transferred items.
  #
  # Example:
  #   inventory.deposit_at_least 5, "diamond_pickaxe" # => 3
  #   inventory.deposit_at_least 5, &.empty?, hotbar # => 1
  #   inventory.deposit_at_least 5, { |slot| slot.item_id == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def deposit_at_least(count, spec, source : Array(WindowSlot) = inventory + hotbar, target : Array(WindowSlot) = content)
    transferred = 0
  
    # prefer large stacks for minimum clicks
    # for equal stacks, preserve order
    source.sort_by { |s| s.count }.each do |slot|
      next unless slot.matches? spec
      
      # Find empty slot in target container
      target_slot = nil
      target.each_with_index do |slot, index|
        if slot.matches?("air")
          target_slot = slot
        end
      end

      break if target_slot.nil? # Target full.

      # Swap slots
      swap_slot = target_slot.slot_nr

      target_slot.slot_nr = slot.slot_nr
      slot.slot_nr = swap_slot

      changed_slots = [
       slot,
       target_slot
      ]

      client.send_packet! Serverbound::ClickWindow.new :shift, 0_u8, slot.slot_nr.to_u16, changed_slots, client.window.id.to_u8, client.window.state_id, slot

      transferred += slot.count

      break if transferred >= count
    end

    client.send_packet! Serverbound::CloseWindow.new client.window.id

    transferred
  end

  def deposit_at_least(count, &spec : WindowSlot -> _)
    deposit_at_least(count, spec)
  end

  # Closes the current open window if any
  def close()
    client.window.close
  end

  private def find_slot(spec, source) 
    source.each_with_index do |slot, index|
      if slot.matches?(spec)
        return slot
      end
    end

    return nil
  end

  private def shift_click_at_least(count, spec, slots : Array(WindowSlot))
    transferred = 0
    # prefer large stacks for minimum clicks
    # for equal stacks, preserve order
    slots.sort_by { |s| s.count }.each do |slot|
      next unless slot.matches? spec
      transferred += slot.count
      click slot, shift: true
      break if transferred >= count
    end
    transferred
  end

  class ItemNotFoundError < Exception; end
end
