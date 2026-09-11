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

  # Selects a matching item into the main hand, if one exists in the inventory.
  # Returns true if an item was picked, false otherwise.
  #
  # Example:
  #   inventory.pick "diamond_pickaxe" # => true
  #   inventory.pick &.empty? # => true
  #   inventory.pick { |slot| slot.name == "diamond_pickaxe" && slot.efficiency >= 4 } # => false
  #
  # ### Durability-aware selection
  #
  # `pick` is smarter than a plain find-and-equip. For each call it:
  #
  # 1. Keeps the main hand if it already matches and is not close to breaking.
  # 2. Otherwise searches the hotbar, picking the **most-damaged usable** tool
  #    first so tools wear out evenly instead of leaving partially-damaged
  #    leftovers.
  # 3. Falls back to the rest of the inventory, swapping the chosen slot into
  #    the hotbar.
  #
  # Because the most-damaged usable tool is chosen each time, calling `pick`
  # regularly in a loop will automatically rotate in fresh tools from the
  # inventory as the hotbar wears down — no manual reselection needed.
  #
  # ### Avoiding tool destruction
  #
  # Slots that `needs_repair?` are treated as if they don't match, so `pick`
  # will not hand you a tool that's about to shatter. "Needs repair" means an
  # **enchanted diamond or netherite tool** with fewer than 12 uses left whose
  # `repair_cost` is still below the cutoff (see below). Such tools are
  # preserved for the anvil.
  #
  # Tools that are **not** worth repairing — unenchanted tools, wood/stone/
  # iron/gold tools, or diamond/netherite tools whose repair cost has climbed
  # above the cutoff — are still selected and will be used until they break.
  # The rationale: if repairing costs too many levels, it's cheaper to craft a
  # fresh one.
  #
  # ### Tuning the repair cutoff
  #
  # The cutoff is `Rosegold::Slot.max_repair_cost` (default `31`). Raise it to
  # keep babying heavily-repaired tools, or lower it to retire them sooner:
  #
  #   Rosegold::Slot.max_repair_cost = 15  # retire tools past "Prior Work: 15"
  #   Rosegold::Slot.max_repair_cost = 0   # never preserve — use everything to breakage
  def pick(spec)
    return true if main_hand.matches?(spec) && !main_hand.needs_repair?

    # Sort hotbar by durability (lower durability first) while preserving index mapping
    hotbar_with_indices = hotbar_slots.map_with_index { |slot, index| {slot, index} }
    sorted_hotbar = hotbar_with_indices.sort_by { |slot_index_pair|
      slot = slot_index_pair[0]
      max_durability = slot.max_durability
      if max_durability > 0
        [slot.durability, slot.count.to_i8]
      else
        [Int32::MAX, slot.count.to_i8]
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

  def pick(&spec : Slot -> _)
    pick(spec)
  end

  def pick!(spec)
    pick(spec) || raise ItemNotFoundError.new("Item #{spec} not found in inventory")
  end

  def pick!(&spec : Slot -> _)
    pick!(spec)
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
    log = Log.for("refill_hand")

    menu = @client.inventory_menu
    if @client.container_menu != menu
      Log.warn { "Cannot refill hand while container is open" }
      return main_hand.count.to_i32
    end

    return 0 if main_hand.empty?
    return main_hand.count.to_i32 unless menu.cursor.empty?

    target = menu.copy_slot(main_hand)
    max_stack_size = main_hand.max_stack_size.to_i32

    log.debug { "refill_hand: main_hand=#{main_hand.name}x#{main_hand.count}, target_id=#{target.item_id_int}, max_stack=#{max_stack_size}, hotbar_sel=#{@client.player.hotbar_selection}, state_id=#{menu.state_id}" }

    return main_hand.count.to_i32 if main_hand.count.to_i32 >= max_stack_size

    current_hotbar_selection = @client.player.hotbar_selection.to_i32

    refill_hand_from_inventory(target, current_hotbar_selection, max_stack_size, log)

    # Number-key staging works even when every main-inventory slot is occupied.
    8.times do
      break if main_hand.count.to_i32 >= max_stack_size
      break if inventory.any? { |slot| refill_hand_matches?(slot, target) }

      donor = refill_hand_hotbar_donor(target, current_hotbar_selection)
      break unless donor

      count_before = main_hand.count.to_i32
      donor_hotbar_index = donor.slot_number - menu.hotbar_slot_index(0)

      displaced_slot = inventory.first?
      break unless displaced_slot

      menu.swap_hotbar(donor_hotbar_index, displaced_slot)
      @client.wait_tick
      refill_hand_from_inventory(target, current_hotbar_selection, max_stack_size, log)

      break if main_hand.count.to_i32 <= count_before
    end

    main_hand.count.to_i32
  end

  # Quick-move fills hotbar slots left to right, so temporarily give the hand
  # the earliest compatible partial stack's priority, then restore it.
  private def refill_hand_from_inventory(target : Rosegold::Slot, selected_hotbar_index : Int32, max_stack_size : Int32, log)
    menu = @client.inventory_menu
    return unless inventory.any? { |slot| refill_hand_matches?(slot, target) }

    selected_slot_number = menu.hotbar_slot_index(selected_hotbar_index)
    priority_slot = hotbar.find { |slot| refill_hand_matches?(slot, target) && slot.count.to_i32 < max_stack_size }
    staged_slot_number = priority_slot ? priority_slot.slot_number : selected_slot_number
    swapped = staged_slot_number != selected_slot_number

    if swapped
      menu.swap_hotbar(selected_hotbar_index, staged_slot_number)
      @client.wait_tick
    end

    begin
      27.times do
        staged_stack = menu[staged_slot_number]
        break if staged_stack.count.to_i32 >= max_stack_size

        source = inventory.find { |slot| refill_hand_matches?(slot, target) }
        break unless source

        count_before = staged_stack.count.to_i32
        log.debug { "refill_hand: shift-clicking slot #{source.slot_number} (#{source.name}x#{source.count}), state_id=#{menu.state_id}" }
        menu.send_click source.slot_number, 0, :shift
        @client.wait_tick

        break if menu[staged_slot_number].count.to_i32 <= count_before
      end
    ensure
      if swapped
        menu.swap_hotbar(selected_hotbar_index, staged_slot_number)
        @client.wait_tick
      end
    end
  end

  private def refill_hand_hotbar_donor(target : Rosegold::Slot, selected_hotbar_index : Int32) : Rosegold::WindowSlot?
    hotbar.find do |slot|
      slot.slot_number != @client.inventory_menu.hotbar_slot_index(selected_hotbar_index) &&
        refill_hand_matches?(slot, target)
    end
  end

  private def refill_hand_matches?(slot : Rosegold::Slot, target : Rosegold::Slot) : Bool
    slot.count > 0 && @client.inventory_menu.same_item_same_components?(slot, target)
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

  # Helper method to sort slots by durability (lower durability first), then by stack size (smaller stacks first)
  private def sort_by_durability_and_count(slots : Array(WindowSlot))
    slots.sort_by { |slot|
      max_durability = slot.max_durability
      if max_durability > 0
        [slot.durability, slot.count.to_i8]
      else
        [Int32::MAX, slot.count.to_i8]
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
      @client.wait_tick # Wait for server to process and sync state
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
