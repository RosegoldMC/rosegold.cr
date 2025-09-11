require "./slot"

# Shared operations for inventory and container menus
# Extracts common logic from both ContainerMenu and InventoryMenu
module Rosegold::InventoryOperations
  # Check if two slots have the same item and components (for stacking)
  def same_item_same_components?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return false if slot1.empty? || slot2.empty?

    slot1.item_id_int == slot2.item_id_int &&
      slot1.components_to_add == slot2.components_to_add &&
      slot1.components_to_remove == slot2.components_to_remove
  end

  # Get max stack size for an item
  def get_max_stack_size(item_slot : Rosegold::Slot) : Int32
    item_slot.empty? ? 64 : item_slot.max_stack_size.to_i
  end

  # Create a deep copy of a slot
  def copy_slot(slot : Rosegold::Slot) : Rosegold::Slot
    Rosegold::Slot.new(slot.count, slot.item_id_int, slot.components_to_add.dup, slot.components_to_remove.dup)
  end

  # Vanilla's safeInsert equivalent - safely insert items from cursor to slot
  def safe_insert(target_slot_index : Int32, cursor_slot : Rosegold::Slot, amount : Int32)
    # Return cursor unchanged if empty or can't place in this slot
    return cursor_slot if cursor_slot.empty? || !may_place?(target_slot_index, cursor_slot)

    target_slot = self[target_slot_index]
    max_stack_size = get_slot_max_stack_size(target_slot_index, cursor_slot)

    # Calculate how many items we can actually place
    transfer_amount = [amount, cursor_slot.count.to_i, max_stack_size - target_slot.count.to_i].min
    return cursor_slot if transfer_amount <= 0

    if target_slot.empty?
      # Empty slot - place items directly
      new_target = copy_slot(cursor_slot)
      new_target.count = transfer_amount.to_u32
      self[target_slot_index] = new_target

      # Shrink cursor
      cursor_slot.count -= transfer_amount.to_u32
      cursor_slot.count == 0 ? Rosegold::Slot.new : cursor_slot
    elsif same_item_same_components?(target_slot, cursor_slot)
      # Same items - merge stacks
      target_slot.count += transfer_amount.to_u32
      cursor_slot.count -= transfer_amount.to_u32
      cursor_slot.count == 0 ? Rosegold::Slot.new : cursor_slot
    else
      # Different items or can't stack
      cursor_slot
    end
  end

  # Vanilla's tryRemove/safeTake equivalent - safely take items from slot
  def safe_take(source_slot_index : Int32, amount : Int32)
    source_slot = self[source_slot_index]

    # Return nil if can't pickup from this slot
    return nil if !may_pickup?(source_slot_index)

    # Return nil if slot doesn't allow modification and we're taking partial amount
    if !allow_modification?(source_slot_index) && amount < source_slot.count.to_i
      return nil
    end

    return nil if source_slot.empty?

    actual_amount = [amount, source_slot.count.to_i].min
    return nil if actual_amount == 0

    # Create taken item stack
    taken = copy_slot(source_slot)
    taken.count = actual_amount.to_u32

    # Update the source slot
    if actual_amount >= source_slot.count.to_i
      self[source_slot_index] = Rosegold::Slot.new # Empty slot
    else
      source_slot.count -= actual_amount.to_u32
    end

    {taken: taken, remaining_slot: self[source_slot_index]}
  end

  # Vanilla's moveItemStackTo equivalent - exact implementation from AbstractContainerMenu.java
  def move_item_stack_to(source_index : Int32, target_start : Int32, target_end : Int32, reverse : Bool = false) : Bool
    source_slot = self[source_index]
    return false if source_slot.empty?

    moved_any = false

    # Phase 1: Try to merge with existing stacks (if stackable)
    if source_slot.count > 1 || get_max_stack_size(source_slot) > 1
      if reverse
        index = target_end - 1
        while index >= target_start && source_slot.count > 0
          target_slot = self[index]
          if !target_slot.empty? && same_item_same_components?(source_slot, target_slot)
            max_stack = get_max_stack_size(target_slot)
            transfer_amount = [source_slot.count.to_i, max_stack - target_slot.count.to_i].min
            if transfer_amount > 0
              target_slot.count += transfer_amount.to_u32
              source_slot.count -= transfer_amount.to_u32
              moved_any = true
            end
          end
          index -= 1
        end
      else
        index = target_start
        while index < target_end && source_slot.count > 0
          target_slot = self[index]
          if !target_slot.empty? && same_item_same_components?(source_slot, target_slot)
            max_stack = get_max_stack_size(target_slot)
            transfer_amount = [source_slot.count.to_i, max_stack - target_slot.count.to_i].min
            if transfer_amount > 0
              target_slot.count += transfer_amount.to_u32
              source_slot.count -= transfer_amount.to_u32
              moved_any = true
            end
          end
          index += 1
        end
      end
    end

    # Phase 2: Try to place in empty slots if there are still items
    if source_slot.count > 0
      if reverse
        index = target_end - 1
        while index >= target_start
          if self[index].empty?
            self[index] = copy_slot(source_slot)
            source_slot.count = 0_u32
            moved_any = true
            break
          end
          index -= 1
        end
      else
        index = target_start
        while index < target_end
          if self[index].empty?
            self[index] = copy_slot(source_slot)
            source_slot.count = 0_u32
            moved_any = true
            break
          end
          index += 1
        end
      end
    end

    # Update source slot if it's now empty
    if source_slot.count == 0
      self[source_index] = Rosegold::Slot.new
    end

    moved_any
  end

  # Check if two slots can be stacked together
  def can_stack?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return false if slot1.empty? || slot2.empty?
    return false if slot1.item_id_int != slot2.item_id_int
    return false if slot1.components_to_add != slot2.components_to_add
    return false if slot1.components_to_remove != slot2.components_to_remove

    max_stack = [slot1.max_stack_size, slot2.max_stack_size].min
    (slot1.count + slot2.count) <= max_stack
  end

  # Abstract methods that must be implemented by including classes
  abstract def [](index : Int32) : Rosegold::Slot
  abstract def []=(index : Int32, slot : Rosegold::Slot)

  # Vanilla state ID increment with 15-bit wraparound (matches vanilla's incrementStateId)
  def increment_state_id : UInt32
    @state_id = (@state_id + 1) & 32767
    @state_id
  end

  # Helper method to compare if two slots are equivalent (vanilla's ItemStack.matches equivalent)
  def slots_match?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return true if slot1.empty? && slot2.empty?
    return false if slot1.empty? != slot2.empty?

    slot1.item_id_int == slot2.item_id_int &&
      slot1.count == slot2.count &&
      slot1.components_to_add == slot2.components_to_add &&
      slot1.components_to_remove == slot2.components_to_remove
  end

  # Cursor slot management
  def cursor : Rosegold::Slot
    @cursor
  end

  def cursor=(cursor : Rosegold::Slot)
    @cursor = cursor
  end

  # Player inventory delegation methods
  def hotbar_slots : Array(Rosegold::Slot)
    @player_inventory.hotbar
  end

  def main_inventory_slots : Array(Rosegold::Slot)
    @player_inventory.main_inventory
  end

  def main_hand : Rosegold::Slot
    @player_inventory.selected_slot(@client.player.hotbar_selection.to_u8)
  end

  # Send container click packet with vanilla client-side logic
  def send_click(slot_index : Int32, button : Int32, click_type)
    # Convert symbol to Mode enum
    mode = case click_type
           when :click  then Serverbound::ClickWindow::Mode::Click
           when :shift  then Serverbound::ClickWindow::Mode::Shift
           when :swap   then Serverbound::ClickWindow::Mode::Swap
           when :middle then Serverbound::ClickWindow::Mode::Middle
           when :drop   then Serverbound::ClickWindow::Mode::Drop
           when :drag   then Serverbound::ClickWindow::Mode::Drag
           when :double then Serverbound::ClickWindow::Mode::Double
           else              Serverbound::ClickWindow::Mode::Click
           end

    # VANILLA PATTERN: Capture slot states BEFORE performing click operation
    before_slots = Array.new(total_slots) do |i|
      copy_slot(self[i])
    end

    # Handle special slots first (vanilla behavior)
    if slot_index == -999
      # Slot -999: Click outside inventory (cursor drop)
      perform_cursor_drop_operation(button)
    elsif click_type == :swap && button == 40
      # Button 40: Off-hand swap (F key)
      perform_offhand_swap_operation(slot_index)
    else
      # Regular click operations
      case click_type
      when :shift
        perform_shift_click(slot_index)
      when :click
        perform_regular_click(slot_index, button)
      when :swap
        perform_hotbar_swap(slot_index, button)
      when :drop
        perform_drop_operation(slot_index, button)
        # Other operations can be added as needed
      end
    end

    # VANILLA PATTERN: Compare before/after to detect actual changes
    changed_slots = [] of Rosegold::WindowSlot
    total_slots.times do |i|
      before_slot = before_slots[i]
      after_slot = self[i]
      if !slots_match?(before_slot, after_slot)
        changed_slots << Rosegold::WindowSlot.new(i, after_slot)
      end
    end

    # Always send current cursor state (vanilla behavior)
    cursor_slot = @cursor

    # Increment state ID for all operations (matching vanilla)
    increment_state_id

    Log.debug { "Click #{click_type}: changed #{changed_slots.size} slots, new state_id: #{@state_id}" }

    packet = Serverbound::ClickWindow.new(mode, button.to_i8, slot_index.to_i16, changed_slots, menu_id, @state_id.to_i32, cursor_slot)
    @client.send_packet!(packet)
  end

  abstract def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
  abstract def may_pickup?(slot_index : Int32) : Bool
  abstract def allow_modification?(slot_index : Int32) : Bool
  abstract def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
  abstract def menu_id : UInt8
  abstract def total_slots : Int32

  # Shared cursor drop operation (identical in both menus)
  def perform_cursor_drop_operation(button : Int32)
    # Slot -999: Click outside inventory to drop cursor items
    return if @cursor.empty?

    if button == 0
      # Left click: Drop entire stack
      @cursor = Rosegold::Slot.new
    else
      # Right click: Drop single item
      if @cursor.count > 1
        @cursor.count -= 1
      else
        @cursor = Rosegold::Slot.new
      end
    end
  end

  # Shared regular click operation (identical vanilla logic in both menus)
  def perform_regular_click(slot_index : Int32, button : Int32)
    # VANILLA LOGIC: Based on AbstractContainerMenu.doClick() lines 452-483
    return if slot_index < 0 || slot_index >= total_slots

    clicked_slot = self[slot_index]
    cursor_slot = @cursor
    is_primary = button == 0 # PRIMARY (left click) vs SECONDARY (right click)

    # CASE 1: Empty slot + non-empty cursor
    if clicked_slot.empty?
      if !cursor_slot.empty? && may_place?(slot_index, cursor_slot)
        # Insert from cursor to slot
        amount_to_place = is_primary ? cursor_slot.count.to_i : 1
        @cursor = safe_insert(slot_index, cursor_slot, amount_to_place)
      end
      # CASE 2: Non-empty slot + empty cursor
    elsif cursor_slot.empty?
      if may_pickup?(slot_index)
        # Take from slot to cursor
        amount_to_take = is_primary ? clicked_slot.count.to_i : (clicked_slot.count.to_i + 1) // 2
        take_result = safe_take(slot_index, amount_to_take)
        if take_result
          @cursor = take_result[:taken]
          self[slot_index] = take_result[:remaining_slot]
        end
      end
      # CASE 3: Both slots non-empty
    else
      if may_pickup?(slot_index)
        if may_place?(slot_index, cursor_slot)
          # Same items - try to merge
          if same_item_same_components?(clicked_slot, cursor_slot)
            amount_to_merge = is_primary ? cursor_slot.count.to_i : 1
            @cursor = safe_insert(slot_index, cursor_slot, amount_to_merge)
            # Different items - try to swap if cursor fits in slot
          elsif cursor_slot.count <= get_slot_max_stack_size(slot_index, cursor_slot).to_u32
            temp = copy_slot(clicked_slot)
            self[slot_index] = copy_slot(cursor_slot)
            @cursor = temp
          end
          # Same items but can't place - try to take from slot to cursor
        elsif same_item_same_components?(clicked_slot, cursor_slot)
          max_cursor_size = get_max_stack_size(cursor_slot)
          available_space = max_cursor_size - cursor_slot.count.to_i
          amount_to_take = [clicked_slot.count.to_i, available_space].min

          if amount_to_take > 0
            take_result = safe_take(slot_index, amount_to_take)
            if take_result
              cursor_slot.count += take_result[:taken].count
              self[slot_index] = take_result[:remaining_slot]
            end
          end
        end
      end
    end
  end

  # Shared slot conversion to WindowSlots (identical in both menus)
  def slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(total_slots)
    (0...total_slots).each do |index|
      slot = self[index]
      result << Rosegold::WindowSlot.new(index, slot)
    end
    result
  end

  def slots=(new_slots : Array(Rosegold::WindowSlot))
    # Convert WindowSlots back to regular slots and update the menu
    regular_slots = new_slots.map(&.as(Rosegold::Slot))
    update_all_slots(regular_slots, @cursor, @state_id)
  end

  # Update all slots from SetContainerContent packet (vanilla behavior - no validation)
  def update_all_slots(slots : Array(Rosegold::Slot), cursor : Rosegold::Slot, packet_state_id : UInt32)
    # Follow vanilla behavior: simply accept the server's state ID without validation
    @state_id = packet_state_id

    slots.each_with_index do |slot, index|
      if index < total_slots
        self[index] = slot
      end
    end
    @cursor = cursor

    # Update remote slots to match what server sent (vanilla behavior)
    slots.each_with_index do |slot, index|
      if index < @remote_slots.size
        @remote_slots[index].force(slot)
      end
    end
    @remote_cursor.force(cursor)
  end

  # Update single slot (vanilla behavior - no validation)
  def update_slot(index : Int32, slot : Rosegold::Slot, packet_state_id : UInt32)
    # Follow vanilla behavior: simply accept the server's state ID without validation
    @state_id = packet_state_id

    if index >= 0 && index < total_slots
      self[index] = slot
      # Update remote slot to match what server sent (vanilla behavior)
      if index < @remote_slots.size
        @remote_slots[index].force(slot)
      end
    elsif index == -1
      # Cursor slot
      @cursor = slot
      @remote_cursor.force(slot)
    end
  end

  # Check for desync and request refresh if needed (vanilla-style recovery)
  def check_and_fix_desync
    has_desync = false

    # Check each slot for desync
    total_slots.times do |i|
      local_slot = self[i]
      remote_slot = @remote_slots[i]

      if !remote_slot.matches?(local_slot)
        Log.debug { "Detected slot desync at index #{i}: local=#{local_slot}, remote=#{remote_slot.slot}" }
        has_desync = true
      end
    end

    # Check cursor desync
    if !@remote_cursor.matches?(@cursor)
      Log.debug { "Detected cursor desync: local=#{@cursor}, remote=#{@remote_cursor.slot}" }
      has_desync = true
    end

    if has_desync
      Log.info { "Requesting resync due to detected desync" }
      request_resync
    end
  end

  # Request a full resync from server (vanilla approach)
  private def request_resync
    # In vanilla, clicking on an invalid slot forces server to send full content
    # We'll use slot -999 (outside container) to trigger this
    packet = Serverbound::ClickWindow.new(
      Serverbound::ClickWindow::Mode::Click,
      0_i8,     # left click
      -999_i16, # outside container slot
      [] of Rosegold::WindowSlot,
      menu_id,
      @state_id.to_i32,
      @cursor
    )
    @client.send_packet!(packet)
    Log.debug { "Sent resync request via click outside container" }
  end

  # Shared drop operation (identical in both menus)
  def perform_drop_operation(slot_index : Int32, button : Int32)
    # Vanilla drop operation (THROW) - matches AbstractContainerMenu.java lines 528-548
    return unless slot_index >= 0 && @cursor.empty?
    return unless slot_index < total_slots

    source_slot = self[slot_index]
    drop_amount = button == 0 ? 1 : source_slot.count.to_i

    # Use safe_take to handle the drop with proper validation (vanilla's safeTake equivalent)
    result = safe_take(slot_index, drop_amount)
    return unless result

    taken_item = result[:taken]
    Log.debug { "DROP: Dropped #{taken_item.count}x #{taken_item.name || "unknown"} from slot #{slot_index}" }

    # For button == 1 (Ctrl+Q), vanilla drops the entire stack in a loop
    # This is handled by the single safe_take call above since we pass the full count
  end

  # Shared off-hand swap operation (identical in both menus)
  def perform_offhand_swap_operation(slot_index : Int32)
    # Button 40: Swap with off-hand slot (F key)
    return if slot_index < 0 || slot_index >= total_slots

    # Get off-hand slot index (different calculation per menu type)
    offhand_index = offhand_slot_index
    return if offhand_index >= total_slots

    # Swap the slots
    temp = copy_slot(self[slot_index])
    self[slot_index] = copy_slot(self[offhand_index])
    self[offhand_index] = temp
  end

  # Shared hotbar swap operation with abstracted slot calculations
  def swap_hotbar(hotbar_nr, slot_number)
    return if slot_number < 0 || slot_number >= total_slots || hotbar_nr < 0 || hotbar_nr >= 9

    # VANILLA PATTERN: Capture before state
    before_slots = Array.new(total_slots) do |i|
      copy_slot(self[i])
    end

    # Perform local swap using abstracted hotbar calculation
    hotbar_slot_index = hotbar_slot_index(hotbar_nr.to_i32)
    if hotbar_slot_index < total_slots
      current_slot = self[slot_number]
      hotbar_slot = self[hotbar_slot_index]
      self[slot_number] = hotbar_slot
      self[hotbar_slot_index] = current_slot
    end

    # VANILLA PATTERN: Compare before/after to detect changes
    changed_slots = [] of Rosegold::WindowSlot
    total_slots.times do |i|
      before_slot = before_slots[i]
      after_slot = self[i]
      if !slots_match?(before_slot, after_slot)
        changed_slots << Rosegold::WindowSlot.new(i, after_slot)
      end
    end

    # Increment state ID and send packet with actual changes
    increment_state_id
    packet = Serverbound::ClickWindow.new(
      Serverbound::ClickWindow::Mode::Swap,
      hotbar_nr.to_i8,
      slot_number.to_i16,
      changed_slots,
      menu_id,
      @state_id.to_i32,
      @cursor
    )
    @client.send_packet!(packet)
  end

  def swap_hotbar(hotbar_nr, slot : Rosegold::WindowSlot)
    swap_hotbar(hotbar_nr, slot.slot_number)
  end

  # Shared hotbar swap for click operations (identical validation logic)
  def perform_hotbar_swap(slot_index : Int32, button : Int32)
    # Vanilla hotbar swap with proper validation
    return if slot_index < 0 || slot_index >= total_slots || button < 0 || button >= 9

    hotbar_slot_index = hotbar_slot_index(button.to_i32)
    return if hotbar_slot_index >= total_slots

    slot_item = self[slot_index]
    hotbar_item = self[hotbar_slot_index]

    # Check if the swap is valid according to vanilla rules
    can_place_slot_in_hotbar = hotbar_item.empty? || may_place?(hotbar_slot_index, slot_item)
    can_place_hotbar_in_slot = slot_item.empty? || may_place?(slot_index, hotbar_item)

    can_pickup_from_slot = slot_item.empty? || may_pickup?(slot_index)
    can_pickup_from_hotbar = hotbar_item.empty? || may_pickup?(hotbar_slot_index)

    # Only proceed if all validation checks pass
    if can_place_slot_in_hotbar && can_place_hotbar_in_slot && can_pickup_from_slot && can_pickup_from_hotbar
      temp = copy_slot(slot_item)
      self[slot_index] = copy_slot(hotbar_item)
      self[hotbar_slot_index] = temp
    end
  end

  # Shared compatibility methods
  def content : Array(Rosegold::WindowSlot)
    content_slots
  end

  def inventory : Array(Rosegold::WindowSlot)
    inventory_slots
  end

  def hotbar : Array(Rosegold::WindowSlot)
    hotbar_slots
  end

  def to_s(io)
    io.print "#{self.class.name}[#{menu_id}: #{total_slots} slots]"
  end

  # Abstract methods for slot index calculations (different per menu type)
  abstract def offhand_slot_index : Int32
  abstract def hotbar_slot_index(hotbar_nr : Int32) : Int32
  abstract def content_slots : Array(Rosegold::WindowSlot)
  abstract def inventory_slots : Array(Rosegold::WindowSlot)
  abstract def hotbar_slots : Array(Rosegold::WindowSlot)

  # Keep existing abstract methods
  abstract def perform_shift_click(slot_index : Int32)
  abstract def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
  abstract def may_pickup?(slot_index : Int32) : Bool
  abstract def allow_modification?(slot_index : Int32) : Bool
  abstract def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
  abstract def menu_id : UInt8
  abstract def total_slots : Int32
end
