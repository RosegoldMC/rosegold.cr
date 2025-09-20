require "./slot"
require "./player_inventory"
require "./remote_slot"
require "./inventory_operations"
require "./item_constants"
require "./slot_offsets"
require "../models/chat"

# Container menu that acts as a view combining container slots + player inventory.
# This follows vanilla Minecraft's AbstractContainerMenu approach.
class Rosegold::ContainerMenu
  include InventoryOperations
  @client : Client

  getter id : UInt8
  getter title : Chat
  getter type_id : UInt32
  property state_id : UInt32 = 0

  # Container-specific slots (excluding player inventory)
  @container_slots : Array(Rosegold::Slot)

  # Reference to persistent player inventory
  @player_inventory : PlayerInventory

  # Cursor slot (what player is carrying)
  @cursor : Rosegold::Slot = Rosegold::Slot.new

  # Container size (number of non-player-inventory slots)
  getter container_size : Int32

  # Remote slot tracking (what server thinks slots should contain)
  @remote_slots : Array(RemoteSlot)
  @remote_cursor : RemoteSlot = RemoteSlot.new

  # Quickcraft (drag) state tracking (vanilla AbstractContainerMenu pattern)
  @quickcraft_status : Int32 = ItemConstants::Quickcraft::START
  @quickcraft_type : Int32 = -1                   # 0=CHARITABLE, 1=GREEDY, 2=CLONE
  @quickcraft_slots : Set(Int32) = Set(Int32).new # Slots being dragged over

  def initialize(@client, @id, @title, @type_id, @container_size)
    # Validate container size matches expected size for menu type (vanilla checkContainerSize)
    validate_container_size(@type_id, @container_size)

    @container_slots = Array.new(@container_size) { Rosegold::Slot.new }
    @player_inventory = @client.player_inventory
    @remote_slots = Array.new(total_slots) { RemoteSlot.new }
  end

  # Open a new container (following vanilla approach)
  def self.open(client : Client, container_id : UInt8, title : Chat, type_id : UInt32, container_size : Int32)
    if client.container_menu != client.inventory_menu
      client.container_menu.as(ContainerMenu).handle_close
    end

    new_container = ContainerMenu.new(client, container_id, title, type_id, container_size)
    client.container_menu = new_container
    new_container
  end

  # Close current container and return to inventory menu
  def self.close(client : Client)
    if client.container_menu != client.inventory_menu
      client.container_menu.as(ContainerMenu).handle_close
      client.container_menu = client.inventory_menu
    end
  end

  # Total number of slots in this menu (container + player inventory)
  def total_slots : Int32
    @container_size + PlayerInventory::INVENTORY_SIZE
  end

  # Get slot by absolute index in the container menu
  def [](index : Int32) : Rosegold::Slot
    if index < 0
      raise ArgumentError.new("Slot index cannot be negative")
    elsif index < @container_size
      # Container slot
      @container_slots[index]
    elsif index < total_slots
      # Player inventory slot - handle network order mapping
      player_index = index - @container_size

      # Container menus use network order: [main inventory(0-26), hotbar(27-35)]
      # PlayerInventory uses internal order: [hotbar(0-8), main(9-35)]
      if player_index < 27
        # Network main inventory (0-26) → PlayerInventory main (9-35)
        internal_index = player_index + 9
      else
        # Network hotbar (27-35) → PlayerInventory hotbar (0-8)
        internal_index = player_index - 27
      end

      @player_inventory[internal_index]
    else
      raise ArgumentError.new("Slot index #{index} out of bounds for container with #{total_slots} slots")
    end
  end

  # Set slot by absolute index in the container menu
  def []=(index : Int32, slot : Rosegold::Slot)
    if index < 0
      raise ArgumentError.new("Slot index cannot be negative")
    elsif index < @container_size
      # Container slot
      @container_slots[index] = slot
    elsif index < total_slots
      # Player inventory slot - handle network order mapping
      player_index = index - @container_size

      # Container menus use network order: [main inventory(0-26), hotbar(27-35)]
      # PlayerInventory uses internal order: [hotbar(0-8), main(9-35)]
      if player_index < 27
        # Network main inventory (0-26) → PlayerInventory main (9-35)
        internal_index = player_index + 9
      else
        # Network hotbar (27-35) → PlayerInventory hotbar (0-8)
        internal_index = player_index - 27
      end

      @player_inventory[internal_index] = slot
    else
      raise ArgumentError.new("Slot index #{index} out of bounds for container with #{total_slots} slots")
    end
  end

  # Container-specific slots only
  def container_slots : Array(Rosegold::Slot)
    @container_slots
  end

  # Player inventory slots (as they appear in this container menu)
  def player_inventory_slots : Array(Rosegold::Slot)
    @player_inventory.items
  end

  # Update all container slots from packet data
  def update_container_slots(slots : Array(Rosegold::Slot))
    size = Math.min(slots.size, @container_size)
    size.times do |i|
      @container_slots[i] = slots[i]
    end
  end

  # Override update_all_slots to handle container-specific slot layout
  def update_all_slots(slots : Array(Rosegold::Slot), cursor : Rosegold::Slot, packet_state_id : UInt32)
    log = Log.for("update_all_slots")

    # Follow vanilla behavior: simply accept the server's state ID without validation
    old_state_id = @state_id
    @state_id = packet_state_id

    log.debug { "Container update: id=#{@id}, state_id #{old_state_id}→#{packet_state_id}, #{slots.size} slots" }

    # First slots are container-specific
    container_slots = slots[0...@container_size]
    update_container_slots(container_slots)

    # Remaining slots are player inventory in network order: [main inventory, hotbar]
    # Network order: [main(0-26), hotbar(27-35)] → PlayerInventory: [hotbar(0-8), main(9-35)]
    if slots.size > @container_size
      player_slots = slots[@container_size...slots.size]

      # Ensure we have exactly 36 slots (27 main + 9 hotbar)
      if player_slots.size == 36
        # Split network order: first 27 are main inventory, last 9 are hotbar
        network_main_inventory = player_slots[0...27] # Network indices 0-26
        network_hotbar = player_slots[27...36]        # Network indices 27-35

        # Map to correct PlayerInventory positions
        @player_inventory.update_slots(network_hotbar, 0)         # Hotbar → slots 0-8
        @player_inventory.update_slots(network_main_inventory, 9) # Main → slots 9-35
      else
        # Fallback for unexpected slot count - use original logic with warning
        log.warn { "Unexpected player inventory slot count: #{player_slots.size}, expected 36" }
        @player_inventory.update_slots(player_slots, 0)
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

  # Send container click packet with vanilla client-side logic (matches handleInventoryMouseClick)
  # Abstract methods required by InventoryOperations
  def menu_id : UInt8
    @id
  end

  # Vanilla-compatible slot validation logic
  private def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    return false if item_slot.empty?

    # Basic validation - most container slots allow any item
    # This matches vanilla Slot.mayPlace() default behavior
    true
  end

  private def may_pickup?(slot_index : Int32) : Bool
    # Basic validation - most slots allow pickup
    # This matches vanilla Slot.mayPickup() default behavior
    true
  end

  # Check if player can modify this slot (vanilla's allowModification logic)
  private def allow_modification?(slot_index : Int32) : Bool
    current_item = self[slot_index]
    may_pickup?(slot_index) && may_place?(slot_index, current_item)
  end

  # Get max stack size that this slot can hold for this item
  private def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    get_max_stack_size(item_slot) # For now, same as item max - could be slot-specific
  end

  # Perform individual click operations (vanilla client-side simulation)
  private def perform_shift_click(slot_index : Int32)
    return if slot_index < 0 || slot_index >= total_slots

    # VANILLA PATTERN: Loop until no more moves possible (AbstractContainerMenu.java lines 430-441)
    clicked_slot = self[slot_index]
    return if clicked_slot.empty?

    original_clicked_slot = copy_slot(clicked_slot)
    moved_item = quick_move_stack(slot_index)

    while !moved_item.empty? && same_item_same_components?(original_clicked_slot, moved_item)
      current_slot = self[slot_index]
      if slots_match?(clicked_slot, current_slot)
        break
      end

      clicked_slot = current_slot
      moved_item = quick_move_stack(slot_index)
    end
  end

  # Vanilla's quickMoveStack equivalent for containers (ChestMenu.java lines 74-96)
  private def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original_item = copy_slot(slot)

    if slot_index < @container_size
      # Move from container to player inventory (reverse order for hotbar priority)
      move_item_stack_to(slot_index, @container_size, total_slots, true)
    else
      # Move from player inventory to container (forward order)
      move_item_stack_to(slot_index, 0, @container_size, false)
    end

    # Update slot state after move (vanilla behavior)
    if self[slot_index].empty?
      self[slot_index] = Rosegold::Slot.new
    end

    original_item
  end

  # Close this container
  def close
    @client.send_packet!(Serverbound::CloseWindow.new(@id.to_u16))
    handle_close
  end

  # Handle container close (vanilla approach)
  def handle_close
    # Simply revert to inventory-only view - DON'T touch the items
    @client.container_menu = @client.inventory_menu
  end

  # Abstract method implementations for InventoryOperations
  def offhand_slot_index : Int32
    SlotOffsets::ContainerMenuOffsets.offhand_slot_index(@container_size)
  end

  def hotbar_slot_index(hotbar_nr : Int32) : Int32
    SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(@container_size, hotbar_nr)
  end

  def content_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(@container_size)
    @container_slots.each_with_index do |slot, index|
      result << Rosegold::WindowSlot.new(index, slot)
    end
    result
  end

  def inventory_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(27)
    @player_inventory.main_inventory.each_with_index do |slot, index|
      absolute_index = SlotOffsets::ContainerMenuOffsets.main_inventory_start_index(@container_size) + index
      result << Rosegold::WindowSlot.new(absolute_index, slot)
    end
    result
  end

  def hotbar_slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(9)
    @player_inventory.hotbar.each_with_index do |slot, index|
      absolute_index = SlotOffsets::ContainerMenuOffsets.hotbar_slot_index(@container_size, index)
      result << Rosegold::WindowSlot.new(absolute_index, slot)
    end
    result
  end

  # Validate container size matches expected size for menu type (vanilla checkContainerSize equivalent)
  private def validate_container_size(type_id : UInt32, size : Int32)
    expected_size = ItemConstants.expected_container_size(type_id)
    return unless expected_size # Unknown container type, accept any size

    if size != expected_size
      Log.warn { "Container size mismatch: type_id=#{type_id} expected=#{expected_size} actual=#{size}" }
      # In vanilla this would throw an exception, but we'll just warn for compatibility
    end
  end

  # QUICKCRAFT (DRAG) OPERATIONS - Vanilla AbstractContainerMenu lines 360-418
  private def perform_quickcraft_operation(slot_index : Int32, button : Int32)
    # Based on vanilla's doClick() ClickType.QUICK_CRAFT handling
    # Three-phase operation: START (0) -> CONTINUE (1) -> END (2)

    previous_status = @quickcraft_status
    @quickcraft_status = get_quickcraft_header(button)

    # Check for invalid state transitions (vanilla line 363)
    if (previous_status != 1 || @quickcraft_status != 2) && previous_status != @quickcraft_status
      reset_quickcraft
      return
    end

    # Cursor must not be empty for quickcraft (vanilla line 365)
    if @cursor.empty?
      reset_quickcraft
      return
    end

    case @quickcraft_status
    when 0 # START: Initialize drag operation
      @quickcraft_type = get_quickcraft_type(button)
      if valid_quickcraft_type?(@quickcraft_type)
        @quickcraft_status = 1
        @quickcraft_slots.clear
        Log.debug { "Starting quickcraft: type=#{@quickcraft_type}" }
      else
        reset_quickcraft
      end
    when 1 # CONTINUE: Add slot to drag selection
      if slot_index >= 0 && slot_index < total_slots
        clicked_slot = self[slot_index]
        cursor_item = @cursor

        # Check if slot can accept the dragged item (vanilla line 378)
        if can_item_quick_replace?(clicked_slot, cursor_item) && may_place?(slot_index, cursor_item) &&
           (@quickcraft_type == 2 || cursor_item.count > @quickcraft_slots.size) && can_drag_to?(slot_index)
          @quickcraft_slots.add(slot_index)
          Log.debug { "Added slot #{slot_index} to quickcraft (#{@quickcraft_slots.size} total)" }
        end
      end
    when 2 # END: Execute drag distribution
      if !@quickcraft_slots.empty?
        # Single slot special case (vanilla line 383-387)
        if @quickcraft_slots.size == 1
          target_slot = @quickcraft_slots.first
          reset_quickcraft
          # Recursively call as regular click
          perform_regular_click(target_slot, @quickcraft_type)
          return
        end

        # Multi-slot distribution (vanilla lines 389-415)
        distribute_items_to_slots
      end

      reset_quickcraft
    end
  end

  # Helper methods for quickcraft operations

  private def get_quickcraft_header(button : Int32) : Int32
    (button >> 2) & 3 # Extract header bits (vanilla getQuickcraftHeader)
  end

  private def get_quickcraft_type(button : Int32) : Int32
    button & 3 # Extract type bits (vanilla getQuickcraftType)
  end

  private def valid_quickcraft_type?(type : Int32) : Bool
    type == 0 || type == 1 || type == 2 # CHARITABLE, GREEDY, CLONE
  end

  private def can_item_quick_replace?(target_slot : Rosegold::Slot, dragged_item : Rosegold::Slot) : Bool
    return true if target_slot.empty?
    return false if dragged_item.empty?

    # Items must be compatible for stacking
    target_slot.item_id_int == dragged_item.item_id_int &&
      target_slot.components_to_add == dragged_item.components_to_add &&
      target_slot.components_to_remove == dragged_item.components_to_remove
  end

  private def can_drag_to?(slot_index : Int32) : Bool
    # Most slots can be dragged to, some exceptions might apply
    # For now, allow all valid slots
    slot_index >= 0 && slot_index < total_slots
  end

  private def distribute_items_to_slots
    # Complex distribution algorithm matching vanilla lines 389-415
    cursor_item = @cursor.dup
    original_count = cursor_item.count
    total_distributed = 0

    # Calculate distribution amount per slot
    amount_per_slot = get_quickcraft_place_count(@quickcraft_slots.size, @quickcraft_type, cursor_item)

    @quickcraft_slots.each do |slot_index|
      target_slot = self[slot_index]

      # Calculate how much can go in this slot
      existing_count = target_slot.empty? ? 0 : target_slot.count
      max_stack = get_max_stack_size_for_slot(slot_index, cursor_item)
      can_place = [amount_per_slot, max_stack - existing_count].min

      if can_place > 0
        if target_slot.empty?
          # Place new stack
          new_slot = cursor_item.dup
          new_slot.count = can_place.to_u8
          self[slot_index] = new_slot
        else
          # Add to existing stack
          target_slot.count = (target_slot.count + can_place).to_u8
        end

        total_distributed += can_place
      end
    end

    # Update cursor with remaining items
    remaining = original_count - total_distributed
    if remaining <= 0
      @cursor = Rosegold::Slot.new # Empty cursor
    else
      @cursor.count = remaining.to_u8
    end

    Log.debug { "Distributed #{total_distributed} items across #{@quickcraft_slots.size} slots" }
  end

  private def get_quickcraft_place_count(slot_count : Int32, quickcraft_type : Int32, item : Rosegold::Slot) : Int32
    # Vanilla getQuickCraftPlaceCount logic
    case quickcraft_type
    when 0 # CHARITABLE: Distribute evenly
      (item.count.to_f / slot_count).floor.to_i
    when 1 # GREEDY: 1 per slot
      1
    when 2 # CLONE: Fill stacks (creative mode)
      item.max_stack_size.to_i
    else
      0
    end
  end

  private def get_max_stack_size_for_slot(slot_index : Int32, item : Rosegold::Slot) : Int32
    # Get max stack size considering both item and slot constraints
    [item.max_stack_size.to_i, 64].min # Most slots have 64 max, some items have less
  end

  private def reset_quickcraft
    @quickcraft_status = ItemConstants::Quickcraft::START
    @quickcraft_slots.clear
    Log.debug { "Reset quickcraft state" }
  end
end
