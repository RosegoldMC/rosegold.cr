require "./slot"
require "./player_inventory"
require "./remote_slot"
require "./item_constants"
require "./slot_offsets"
require "./click_operation"
require "../models/chat"

# Abstract base for all menu types (player inventory, chest, furnace, etc.)
# Replaces the previous InventoryOperations module + InventoryMenu/ContainerMenu split.
abstract class Rosegold::Menu
  @client : Client

  abstract def menu_id : UInt8
  abstract def total_slots : Int32

  # Slot access
  abstract def [](index : Int32) : Rosegold::Slot
  abstract def []=(index : Int32, slot : Rosegold::Slot)

  # Shift-click routing (each menu subclass defines where items move)
  abstract def quick_move_stack(slot_index : Int32) : Rosegold::Slot

  # Slot validation
  abstract def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
  abstract def may_pickup?(slot_index : Int32) : Bool
  abstract def allow_modification?(slot_index : Int32) : Bool
  abstract def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32

  # Slot group accessors
  abstract def offhand_slot_index : Int32
  abstract def hotbar_slot_index(hotbar_nr : Int32) : Int32
  abstract def container_slots : Array(Rosegold::WindowSlot)
  abstract def inventory_slots : Array(Rosegold::WindowSlot)
  abstract def hotbar_window_slots : Array(Rosegold::WindowSlot)

  # Player inventory start offset within this menu
  abstract def player_inventory_start : Int32

  property state_id : UInt32 = 0
  @player_inventory : PlayerInventory
  @cursor : Rosegold::Slot = Rosegold::Slot.new
  @remote_slots : Array(RemoteSlot)
  @remote_cursor : RemoteSlot = RemoteSlot.new

  def initialize(@client, @player_inventory)
    @remote_slots = Array.new(total_slots) { RemoteSlot.new }
  end

  # --- Cursor ---

  def cursor : Rosegold::Slot
    @cursor
  end

  def cursor=(cursor : Rosegold::Slot)
    @cursor = cursor
  end

  # --- Convenience accessors ---

  def content : Array(Rosegold::WindowSlot)
    container_slots
  end

  def inventory : Array(Rosegold::WindowSlot)
    inventory_slots
  end

  def hotbar : Array(Rosegold::WindowSlot)
    hotbar_window_slots
  end

  def player_window_slots : Array(Rosegold::WindowSlot)
    inventory_slots + hotbar_window_slots
  end

  def player_inventory_slots : Array(Rosegold::Slot)
    @player_inventory.items
  end

  def hotbar_slots : Array(Rosegold::Slot)
    @player_inventory.hotbar
  end

  def main_inventory_slots : Array(Rosegold::Slot)
    @player_inventory.main_inventory
  end

  def main_hand : Rosegold::Slot
    @player_inventory.selected_slot(@client.player.hotbar_selection.to_u8)
  end

  def slots : Array(Rosegold::WindowSlot)
    result = Array(Rosegold::WindowSlot).new(total_slots)
    (0...total_slots).each do |index|
      result << Rosegold::WindowSlot.new(index, self[index])
    end
    result
  end

  def slots=(new_slots : Array(Rosegold::WindowSlot))
    regular_slots = new_slots.map(&.as(Rosegold::Slot))
    update_all_slots(regular_slots, @cursor, @state_id)
  end

  def id : UInt8
    menu_id
  end

  def to_s(io)
    io.print "#{self.class.name}[#{menu_id}: #{total_slots} slots]"
  end

  # --- Stack comparison helpers ---

  def same_item_same_components?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return false if slot1.empty? || slot2.empty?
    slot1.item_id_int == slot2.item_id_int &&
      slot1.components_to_add == slot2.components_to_add &&
      slot1.components_to_remove == slot2.components_to_remove
  end

  def get_max_stack_size(item_slot : Rosegold::Slot) : Int32
    item_slot.empty? ? 64 : item_slot.max_stack_size.to_i
  end

  def copy_slot(slot : Rosegold::Slot) : Rosegold::Slot
    Rosegold::Slot.new(slot.count, slot.item_id_int, slot.components_to_add.dup, slot.components_to_remove.dup)
  end

  def slots_match?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return true if slot1.empty? && slot2.empty?
    return false if slot1.empty? != slot2.empty?
    slot1.item_id_int == slot2.item_id_int &&
      slot1.count == slot2.count &&
      slot1.components_to_add == slot2.components_to_add &&
      slot1.components_to_remove == slot2.components_to_remove
  end

  def can_stack?(slot1 : Rosegold::Slot, slot2 : Rosegold::Slot) : Bool
    return false if slot1.empty? || slot2.empty?
    return false if slot1.item_id_int != slot2.item_id_int
    return false if slot1.components_to_add != slot2.components_to_add
    return false if slot1.components_to_remove != slot2.components_to_remove
    max_stack = [slot1.max_stack_size, slot2.max_stack_size].min
    (slot1.count + slot2.count) <= max_stack
  end

  # --- Item movement (vanilla moveItemStackTo) ---

  def safe_insert(target_slot_index : Int32, cursor_slot : Rosegold::Slot, amount : Int32)
    return cursor_slot if cursor_slot.empty? || !may_place?(target_slot_index, cursor_slot)

    target_slot = self[target_slot_index]
    max_stack_size = get_slot_max_stack_size(target_slot_index, cursor_slot)

    transfer_amount = [amount, cursor_slot.count.to_i, max_stack_size - target_slot.count.to_i].min
    return cursor_slot if transfer_amount <= 0

    if target_slot.empty?
      new_target = copy_slot(cursor_slot)
      new_target.count = transfer_amount.to_u32
      self[target_slot_index] = new_target
      cursor_slot.count -= transfer_amount.to_u32
      cursor_slot.count == 0 ? Rosegold::Slot.new : cursor_slot
    elsif same_item_same_components?(target_slot, cursor_slot)
      target_slot.count += transfer_amount.to_u32
      cursor_slot.count -= transfer_amount.to_u32
      cursor_slot.count == 0 ? Rosegold::Slot.new : cursor_slot
    else
      cursor_slot
    end
  end

  def safe_take(source_slot_index : Int32, amount : Int32)
    source_slot = self[source_slot_index]
    return nil if !may_pickup?(source_slot_index)
    if !allow_modification?(source_slot_index) && amount < source_slot.count.to_i
      return nil
    end
    return nil if source_slot.empty?

    actual_amount = [amount, source_slot.count.to_i].min
    return nil if actual_amount == 0

    taken = copy_slot(source_slot)
    taken.count = actual_amount.to_u32

    if actual_amount >= source_slot.count.to_i
      self[source_slot_index] = Rosegold::Slot.new
    else
      source_slot.count -= actual_amount.to_u32
    end

    {taken: taken, remaining_slot: self[source_slot_index]}
  end

  def move_item_stack_to(source_index : Int32, target_start : Int32, target_end : Int32, reverse : Bool = false) : Bool
    source_slot = self[source_index]
    return false if source_slot.empty?

    moved_any = false
    max_source_stack = get_max_stack_size(source_slot)

    # Phase 1: merge with existing stacks
    if source_slot.count > 1 || max_source_stack > 1
      if reverse
        index = target_end - 1
        while index >= target_start && source_slot.count > 0
          target_slot = self[index]
          if !target_slot.empty? && same_item_same_components?(source_slot, target_slot)
            max_stack = get_slot_max_stack_size(index, source_slot)
            available_space = max_stack - target_slot.count.to_i
            transfer_amount = [source_slot.count.to_i, available_space].min
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
            max_stack = get_slot_max_stack_size(index, source_slot)
            available_space = max_stack - target_slot.count.to_i
            transfer_amount = [source_slot.count.to_i, available_space].min
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

    # Phase 2: place in first empty slot (vanilla breaks after first placement)
    if source_slot.count > 0
      if reverse
        index = target_end - 1
        while index >= target_start && source_slot.count > 0
          if self[index].empty? && may_place?(index, source_slot)
            max_in_slot = get_slot_max_stack_size(index, source_slot)
            place_count = [source_slot.count.to_i, max_in_slot].min
            placed = copy_slot(source_slot)
            placed.count = place_count.to_u32
            self[index] = placed
            source_slot.count -= place_count.to_u32
            moved_any = true
            break
          end
          index -= 1
        end
      else
        index = target_start
        while index < target_end && source_slot.count > 0
          if self[index].empty? && may_place?(index, source_slot)
            max_in_slot = get_slot_max_stack_size(index, source_slot)
            place_count = [source_slot.count.to_i, max_in_slot].min
            placed = copy_slot(source_slot)
            placed.count = place_count.to_u32
            self[index] = placed
            source_slot.count -= place_count.to_u32
            moved_any = true
            break
          end
          index += 1
        end
      end
    end

    if source_slot.count == 0
      self[source_index] = Rosegold::Slot.new
    end

    moved_any
  end

  # --- Click operations ---

  def send_click(slot_index : Int32, operation : ClickOperation)
    mode, button = operation.to_mode_and_button
    click_type = case mode
                 when .click?  then :click
                 when .shift?  then :shift
                 when .swap?   then :swap
                 when .middle? then :middle
                 when .drop?   then :drop
                 when .double? then :double
                 else               :click
                 end
    send_click(slot_index, button.to_i32, click_type)
  end

  def send_click(slot_index : Int32, button : Int32, click_type)
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

    before_slots = Array.new(total_slots) do |i|
      copy_slot(self[i])
    end

    if slot_index == -999
      perform_cursor_drop_operation(button)
    elsif click_type == :swap && button == 40
      perform_offhand_swap_operation(slot_index)
    else
      case click_type
      when :shift then perform_shift_click(slot_index)
      when :click then perform_regular_click(slot_index, button)
      when :swap  then perform_hotbar_swap(slot_index, button)
      when :drop  then perform_drop_operation(slot_index, button)
      end
    end

    changed_slots = [] of Rosegold::WindowSlot
    total_slots.times do |i|
      before_slot = before_slots[i]
      after_slot = self[i]
      if !slots_match?(before_slot, after_slot)
        changed_slots << Rosegold::WindowSlot.new(i, after_slot)
      end
    end

    send_state_id = @state_id.to_i32
    packet = Serverbound::ClickWindow.new(mode, button.to_i8, slot_index.to_i16, changed_slots, menu_id, send_state_id, @cursor)
    Log.for("send_click").debug { "ClickWindow: slot=#{slot_index}, mode=#{click_type}, state_id=#{send_state_id}, changed=#{changed_slots.map { |slot| "#{slot.slot_number}:#{slot.name}x#{slot.count}" }}" }
    @client.send_packet!(packet)
  end

  def perform_cursor_drop_operation(button : Int32)
    return if @cursor.empty?
    if button == 0
      @cursor = Rosegold::Slot.new
    else
      if @cursor.count > 1
        @cursor.count -= 1
      else
        @cursor = Rosegold::Slot.new
      end
    end
  end

  def perform_regular_click(slot_index : Int32, button : Int32)
    return if slot_index < 0 || slot_index >= total_slots

    clicked_slot = self[slot_index]
    cursor_slot = @cursor
    is_primary = button == 0

    if clicked_slot.empty?
      if !cursor_slot.empty? && may_place?(slot_index, cursor_slot)
        amount_to_place = is_primary ? cursor_slot.count.to_i : 1
        @cursor = safe_insert(slot_index, cursor_slot, amount_to_place)
      end
    elsif cursor_slot.empty?
      if may_pickup?(slot_index)
        amount_to_take = is_primary ? clicked_slot.count.to_i : (clicked_slot.count.to_i + 1) // 2
        take_result = safe_take(slot_index, amount_to_take)
        if take_result
          @cursor = take_result[:taken]
          self[slot_index] = take_result[:remaining_slot]
        end
      end
    else
      if may_pickup?(slot_index)
        if may_place?(slot_index, cursor_slot)
          if same_item_same_components?(clicked_slot, cursor_slot)
            amount_to_merge = is_primary ? cursor_slot.count.to_i : 1
            @cursor = safe_insert(slot_index, cursor_slot, amount_to_merge)
          elsif cursor_slot.count <= get_slot_max_stack_size(slot_index, cursor_slot).to_u32
            temp = copy_slot(clicked_slot)
            self[slot_index] = copy_slot(cursor_slot)
            @cursor = temp
          end
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

  def perform_shift_click(slot_index : Int32)
    return if slot_index < 0 || slot_index >= total_slots

    clicked_slot = self[slot_index]
    return if clicked_slot.empty?
    return unless may_pickup?(slot_index)

    original_clicked_slot = copy_slot(clicked_slot)
    moved_item = quick_move_stack(slot_index)

    while !moved_item.empty? && original_clicked_slot.item_id_int == moved_item.item_id_int
      current_slot = self[slot_index]
      break if slots_match?(clicked_slot, current_slot)
      clicked_slot = current_slot
      moved_item = quick_move_stack(slot_index)
    end
  end

  def perform_drop_operation(slot_index : Int32, button : Int32)
    return unless slot_index >= 0 && @cursor.empty?
    return unless slot_index < total_slots

    if button == 0
      result = safe_take(slot_index, 1)
      return unless result
      Log.debug { "DROP: Dropped 1x #{result[:taken].name || "unknown"} from slot #{slot_index}" }
    else
      # Drop full stack — loop for slots that auto-refill (e.g. crafting output)
      source_slot = self[slot_index]
      return if source_slot.empty?
      original_item = copy_slot(source_slot)
      loop do
        current = self[slot_index]
        break if current.empty?
        break unless same_item_same_components?(original_item, current)
        result = safe_take(slot_index, current.count.to_i)
        break unless result
        Log.debug { "DROP: Dropped #{result[:taken].count}x #{result[:taken].name || "unknown"} from slot #{slot_index}" }
      end
    end
  end

  def perform_offhand_swap_operation(slot_index : Int32)
    return if slot_index < 0 || slot_index >= total_slots
    offhand_index = offhand_slot_index
    return if offhand_index < 0 || offhand_index >= total_slots

    slot_item = self[slot_index]
    offhand_item = self[offhand_index]

    can_pickup_slot = slot_item.empty? || may_pickup?(slot_index)
    can_pickup_offhand = offhand_item.empty? || may_pickup?(offhand_index)
    can_place_in_slot = offhand_item.empty? || may_place?(slot_index, offhand_item)
    can_place_in_offhand = slot_item.empty? || may_place?(offhand_index, slot_item)

    if can_pickup_slot && can_pickup_offhand && can_place_in_slot && can_place_in_offhand
      temp = copy_slot(slot_item)
      self[slot_index] = copy_slot(offhand_item)
      self[offhand_index] = temp
    end
  end

  def perform_hotbar_swap(slot_index : Int32, button : Int32)
    return if slot_index < 0 || slot_index >= total_slots || button < 0 || button >= 9

    hotbar_idx = hotbar_slot_index(button.to_i32)
    return if hotbar_idx >= total_slots

    slot_item = self[slot_index]
    hotbar_item = self[hotbar_idx]

    can_place_slot_in_hotbar = hotbar_item.empty? || may_place?(hotbar_idx, slot_item)
    can_place_hotbar_in_slot = slot_item.empty? || may_place?(slot_index, hotbar_item)
    can_pickup_from_slot = slot_item.empty? || may_pickup?(slot_index)
    can_pickup_from_hotbar = hotbar_item.empty? || may_pickup?(hotbar_idx)

    if can_place_slot_in_hotbar && can_place_hotbar_in_slot && can_pickup_from_slot && can_pickup_from_hotbar
      temp = copy_slot(slot_item)
      self[slot_index] = copy_slot(hotbar_item)
      self[hotbar_idx] = temp
    end
  end

  def swap_hotbar(hotbar_nr, slot_number)
    return if slot_number < 0 || slot_number >= total_slots || hotbar_nr < 0 || hotbar_nr >= 9

    before_slots = Array.new(total_slots) do |i|
      copy_slot(self[i])
    end

    hotbar_idx = hotbar_slot_index(hotbar_nr.to_i32)
    if hotbar_idx >= 0 && hotbar_idx < total_slots
      current_slot = self[slot_number]
      hotbar_slot = self[hotbar_idx]
      self[slot_number] = hotbar_slot
      self[hotbar_idx] = current_slot
    end

    changed_slots = [] of Rosegold::WindowSlot
    total_slots.times do |i|
      before_slot = before_slots[i]
      after_slot = self[i]
      if !slots_match?(before_slot, after_slot)
        changed_slots << Rosegold::WindowSlot.new(i, after_slot)
      end
    end

    send_state_id = @state_id.to_i32
    packet = Serverbound::ClickWindow.new(
      Serverbound::ClickWindow::Mode::Swap,
      hotbar_nr.to_i8,
      slot_number.to_i16,
      changed_slots,
      menu_id,
      send_state_id,
      @cursor
    )
    @client.send_packet!(packet)
  end

  def swap_hotbar(hotbar_nr, slot : Rosegold::WindowSlot)
    swap_hotbar(hotbar_nr, slot.slot_number)
  end

  # --- State sync ---

  def update_all_slots(slots : Array(Rosegold::Slot), cursor : Rosegold::Slot, packet_state_id : UInt32)
    @state_id = packet_state_id

    slots.each_with_index do |slot, index|
      if index < total_slots
        self[index] = slot
      end
    end

    @cursor = cursor

    slots.each_with_index do |slot, index|
      if index < @remote_slots.size
        @remote_slots[index].force(slot)
      end
    end
    @remote_cursor.force(cursor)
  end

  def update_slot(index : Int32, slot : Rosegold::Slot, packet_state_id : UInt32)
    @state_id = packet_state_id

    if index >= 0 && index < total_slots
      self[index] = slot
      if index < @remote_slots.size
        @remote_slots[index].force(slot)
      end
    elsif index == -1
      @cursor = slot
      @remote_cursor.force(slot)
    end
  end

  def check_and_fix_desync
    has_desync = false

    total_slots.times do |i|
      local_slot = self[i]
      remote_slot = @remote_slots[i]
      if !remote_slot.matches?(local_slot)
        Log.debug { "Detected slot desync at index #{i}: local=#{local_slot}, remote=#{remote_slot.slot}" }
        has_desync = true
      end
    end

    if !@remote_cursor.matches?(@cursor)
      Log.debug { "Detected cursor desync: local=#{@cursor}, remote=#{@remote_cursor.slot}" }
      has_desync = true
    end

    if has_desync
      Log.info { "Requesting resync due to detected desync" }
      request_resync
    end
  end

  private def request_resync
    packet = Serverbound::ClickWindow.new(
      Serverbound::ClickWindow::Mode::Click,
      0_i8,
      -999_i16,
      [] of Rosegold::WindowSlot,
      menu_id,
      @state_id.to_i32,
      @cursor
    )
    @client.send_packet!(packet)
    Log.debug { "Sent resync request via click outside container" }
  end

  # --- Close ---

  def close
    # Default no-op; container menus override
  end

  def handle_close
    # Default no-op; container menus override
  end
end
