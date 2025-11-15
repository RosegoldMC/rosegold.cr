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

  # Tries to transfer at least `count` matching items from the container to the player inventory, using shift-clicking.
  # Returns the number of actually transferred items.
  #
  # Example:
  #   inventory.withdraw_at_least 5, "diamond_pickaxe" # => 3
  #   inventory.withdraw_at_least 5, &.empty? # => 1
  #   inventory.withdraw_at_least 5, { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def withdraw_at_least(count, spec)
    shift_click_at_least count, spec, :container_to_player
  end

  def withdraw_at_least(count, &spec : Slot -> _)
    withdraw_at_least(count, spec)
  end

  # Tries to transfer at least `count` matching items from the player inventory to the container, using shift-clicking.
  # Returns the number of actually transferred items.
  #
  # Example:
  #   inventory.deposit_at_least 5, "diamond_pickaxe" # => 3
  #   inventory.deposit_at_least 5, &.empty? # => 1
  #   inventory.deposit_at_least 5, { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def deposit_at_least(count, spec)
    # If container is not ready, return immediately rather than blocking
    return 0 if content.empty?

    shift_click_at_least count, spec, :player_to_container
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
  #   inventory.replenish 3 { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => 2
  def replenish(count, spec)
    current_count = count(spec, inventory + hotbar)
    return current_count if current_count >= count

    current_count + withdraw_at_least(count - current_count, spec)
  end

  def replenish(count, &spec : Slot -> _)
    replenish(count, spec)
  end

  # Refills the main hand to its maximum stack size by manually combining stacks.
  # Only works when no container is open (player inventory only).
  # Returns the final quantity in the main hand after refilling.
  #
  # Example:
  #   inventory.refill_hand # => 64 (if main hand was stone and got filled to max stack)
  #   inventory.refill_hand # => 32 (if only 32 items were available)
  #   inventory.refill_hand # => 0 (if main hand is empty)
  def refill_hand
    # Check if container is open - if so, warn and return current quantity
    if @client.container_menu != @client.inventory_menu
      Log.warn { "Cannot refill hand while container is open" }
      return main_hand.count.to_i32
    end

    # Get initial state
    return 0 if main_hand.empty?

    target_item_id = main_hand.item_id_int
    max_stack_size = main_hand.max_stack_size.to_i32

    return main_hand.count.to_i32 if main_hand.count.to_i32 >= max_stack_size

    # Get current hotbar selection
    current_hotbar_selection = @client.player.hotbar_selection.to_i32

    # Process main inventory first (shift-clicking moves items TO hotbar)
    loop do
      break if main_hand.count.to_i32 >= max_stack_size

      # Find matching item in main inventory
      matching_slot = inventory.find { |slot|
        slot.item_id_int == target_item_id && slot.count > 0
      }
      break unless matching_slot

      # Shift-click to move items from main inventory to hotbar (stacks with main hand)
      @client.inventory_menu.send_click matching_slot.slot_number, 0, :shift

      # Check if any items were actually transferred
      # If main hand didn't change, we're done with main inventory
      break if main_hand.count.to_i32 >= max_stack_size
    end

    # Then process other hotbar slots - use a two-stage approach for hotbar consolidation
    hotbar_slots_with_matching_items = [] of Int32
    hotbar.each_with_index do |slot, index|
      # Skip the current main hand slot
      next if index == current_hotbar_selection

      # Collect slots with matching items
      if slot.item_id_int == target_item_id && slot.count > 0
        hotbar_slots_with_matching_items << slot.slot_number
      end
    end

    # Stage 1: Move items from other hotbar slots to main inventory (if we have items to consolidate)
    hotbar_slots_with_matching_items.each do |slot_number|
      break if main_hand.count.to_i32 >= max_stack_size
      @client.inventory_menu.send_click slot_number, 0, :shift
    end

    # Stage 2: Move items back from main inventory to main hand
    loop do
      break if main_hand.count.to_i32 >= max_stack_size

      # Find matching item in main inventory that we just moved there
      matching_slot = inventory.find { |slot|
        slot.item_id_int == target_item_id && slot.count > 0
      }
      break unless matching_slot

      # Shift-click to move items from main inventory back to hotbar (stacks with main hand)
      @client.inventory_menu.send_click matching_slot.slot_number, 0, :shift
    end

    main_hand.count.to_i32
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

  private def shift_click_at_least(count, spec, direction : Symbol)
    transferred = 0

    loop do
      current_source_slots = case direction
                             when :container_to_player
                               content
                             when :player_to_container
                               inventory + hotbar
                             else
                               raise ArgumentError.new("Invalid direction: #{direction}")
                             end

      sorted_source = sort_by_durability_and_count(current_source_slots)
      slot_to_transfer = sorted_source.find(&.matches?(spec))
      break if slot_to_transfer.nil?

      player_count_before = count(spec, inventory + hotbar)
      @client.container_menu.send_click slot_to_transfer.slot_number, 0, :shift
      player_count_after = count(spec, inventory + hotbar)

      actual_transferred = case direction
                           when :container_to_player
                             player_count_after - player_count_before
                           when :player_to_container
                             player_count_before - player_count_after
                           else
                             0
                           end

      transferred += actual_transferred

      break if transferred >= count || actual_transferred == 0
    end

    transferred
  end

  # Equipment slot accessors
  delegate helmet, chestplate, leggings, boots, off_hand, to: @client.inventory_menu

  class ItemNotFoundError < Exception; end
end
