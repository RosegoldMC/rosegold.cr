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
    shift_click_at_least count, spec, source, target
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
    shift_click_at_least count, spec, source, target
  end

  def deposit_at_least(count, &spec : WindowSlot -> _)
    deposit_at_least(count, spec)
  end

  private def find_empty_slot(source)
    empty_slot = nil

    source.each do |slot|
      if slot.empty?
        empty_slot = slot
        break
      end
    end

    empty_slot
  end

  private def shift_click_at_least(count, spec, source : Array(WindowSlot), target : Array(WindowSlot))
    transferred = 0

    # prefer large stacks for minimum clicks
    # for equal stacks, preserve order
    source.sort_by { |s| -s.count.to_i8 }.each do |slot|
      next unless slot.matches? spec

      # Find first empty slot in target container
      target_slot = find_empty_slot target

      # If the target container is full; break;
      break if target_slot.nil?

      # Swap slots
      changed_slots = [
        Rosegold::WindowSlot.new(target_slot.slot_number, slot),
        Rosegold::WindowSlot.new(slot.slot_number, target_slot),
      ]

      client.send_packet! Serverbound::ClickWindow.new :shift, 0_i8, slot.slot_number.to_i16, changed_slots, client.window.id.to_u8, client.window.state_id.to_i32, client.window.cursor

      slot.slot_number, target_slot.slot_number = target_slot.slot_number, slot.slot_number

      self.slots = slots.sort_by &.slot_number

      transferred += slot.count

      break if transferred >= count
    end

    transferred
  end

  class ItemNotFoundError < Exception; end
end
