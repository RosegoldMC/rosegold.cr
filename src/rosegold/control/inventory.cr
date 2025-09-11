# Utility methods for interacting with the open window.
class Rosegold::Inventory
  private property client : Client

  def initialize(@client); end

  forward_missing_to @client.container_menu

  # Returns the number of matching items in the player inventory (inventory + hotbar), or in the given slots range.
  #
  # Example:
  #   inventory.count "diamond_pickaxe" # => 2
  #   inventory.count &.empty? # => 2
  #   inventory.count { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 1
  #   inventory.count "stone", slots # => 5 (count in entire window including container)
  def count(spec, slots = player_inventory_slots)
    slots.select(&.matches? spec).sum(&.count.to_i32)
  end

  def count(&spec : Slot -> _)
    count(spec)
  end

  # Picks a matching slot, if it exists in the inventory.
  # Returns true if the item was picked, false otherwise.
  #
  # Example:
  #   inventory.pick "diamond_pickaxe" # => true
  #   inventory.pick &.empty? # => true
  #   inventory.pick { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => false
  def pick(spec)
    return true if main_hand.matches?(spec) && !main_hand.needs_repair?

    # Sort hotbar by durability (lower durability first) while preserving index mapping
    hotbar_with_indices = hotbar_slots.map_with_index { |slot, index| {slot, index} }
    sorted_hotbar = hotbar_with_indices.sort_by { |slot_index_pair|
      slot = slot_index_pair[0]
      max_durability = slot.max_durability
      if max_durability > 0
        # Item has durability - prioritize lower durability (higher damage)
        [slot.durability, -slot.count.to_i8]
      else
        # Item has no durability - use original logic (large stacks first)
        [Int32::MAX, -slot.count.to_i8]
      end
    }

    sorted_hotbar.each do |slot_index_pair|
      slot, index = slot_index_pair
      if slot.matches?(spec) && !slot.needs_repair?
        client.player.hotbar_selection = index.to_u8
        return true
      end
    end

    # Sort all slots by durability for main inventory
    sort_by_durability_and_count(slots).each do |slot|
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
  #   inventory.withdraw_at_least 5, { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def withdraw_at_least(count, spec, source : Array(WindowSlot) = content, target : Array(WindowSlot)? = nil)
    actual_target = target || (inventory + hotbar)
    shift_click_at_least count, spec, source, actual_target
  end

  def withdraw_at_least(count, &spec : Slot -> _)
    withdraw_at_least(count, spec)
  end

  # Tries to transfer at least `count` matching items from the container to the player inventory, using shift-clicking.
  # Returns the number of actually transferred items.
  #
  # Example:
  #   inventory.deposit_at_least 5, "diamond_pickaxe" # => 3
  #   inventory.deposit_at_least 5, &.empty?, hotbar # => 1
  #   inventory.deposit_at_least 5, { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def deposit_at_least(count, spec, source : Array(WindowSlot) = inventory + hotbar, target : Array(WindowSlot) = content)
    shift_click_at_least count, spec, source, target
  end

  def deposit_at_least(count, &spec : Slot -> _)
    deposit_at_least(count, spec)
  end

  # Ensures the player has at least `count` items of the specified type in their inventory.
  # If there are already enough items, returns the current count.
  # If not enough items are present, attempts to withdraw more from a container.
  # Returns the total count after replenishment attempt.
  #
  # Example:
  #   inventory.replenish 10, "stone" # => 10 (if successful)
  #   inventory.replenish 5, "diamond" # => 3 (if only 3 available)
  def replenish(count, item_id)
    current_count = count(item_id, inventory + hotbar)
    return current_count if current_count >= count

    current_count + withdraw_at_least count - current_count, item_id
  end

  # Finds an empty slot in the source
  # In order to match vanilla:
  # When source is the container, prioritize first empty #container slot
  # When source is the player inventory, prioritize rightmost empty #hotbar slot
  # then rightmost empty #inventory slot
  private def find_empty_slot(source)
    empty_slot = nil

    source.sort { |slot_a, slot_b| slot_b.slot_number <=> slot_a.slot_number }.each do |slot|
      if slot.empty?
        empty_slot = slot
        break
      end
    end

    empty_slot
  end

  def throw_all_of(name)
    quantity = 0
    # Collect slot numbers first to avoid iterator invalidation
    slot_numbers_to_drop = [] of Int32

    slots.each do |slot|
      next unless slot.name == name
      quantity += slot.count
      slot_numbers_to_drop << slot.slot_number
    end

    # Drop by slot number to avoid issues with slots array being modified during iteration
    slot_numbers_to_drop.each do |slot_number|
      @client.container_menu.send_click slot_number, 1, :drop
    end

    quantity
  end

  # Helper method to sort slots by durability (lower durability first), then by stack size
  private def sort_by_durability_and_count(slots : Array(WindowSlot))
    slots.sort_by { |slot|
      max_durability = slot.max_durability
      if max_durability > 0
        # Item has durability - prioritize lower durability (higher damage)
        [slot.durability, -slot.count.to_i8]
      else
        # Item has no durability - use original logic (large stacks first)
        [Int32::MAX, -slot.count.to_i8]
      end
    }
  end

  private def shift_click_at_least(count, spec, source : Array(WindowSlot), target : Array(WindowSlot))
    transferred = 0

    # prefer items with lower durability first, then large stacks for minimum clicks
    # for items without durability, fall back to original stack size preference
    sort_by_durability_and_count(source).each do |slot|
      next unless slot.matches? spec

      # Find first empty slot in target container
      target_slot = find_empty_slot target

      # If the target container is full; break;
      break if target_slot.nil?

      # Send shift-click packet to server (with optimistic local updates)
      @client.container_menu.send_click slot.slot_number, 0, :shift

      # Count the transferred amount based on what the slot had
      transferred += slot.count

      break if transferred >= count
    end

    transferred
  end

  # Equipment slot accessors
  delegate helmet, chestplate, leggings, boots, off_hand, to: @client.inventory_menu

  class ItemNotFoundError < Exception; end
end
