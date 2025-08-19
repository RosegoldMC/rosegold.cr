# Slot accessor methods raise an error if the window is not ready.
# Note that slots are still available even after the window has been closed.
class Rosegold::Window
  @client : Client

  getter id : UInt8

  getter title : Chat

  # PlayerWindow reuses id 0
  getter type_id : UInt32

  # Inventory and hotbar are at the end of `slots` in all windows except the player inventory.
  @inventory_start : Int32 = -36

  # Used for tracking synchronization with the server.
  property state_id : UInt32 = 0

  # `nil` if window is not ready
  @slots : Array(WindowSlot)?

  # `nil` if window is not ready
  @cursor : WindowSlot?

  # If true, this window will never become ready in the future.
  property? closed : Bool = false

  def initialize(@client, @id, @title, @type_id); end

  def close
    return if closed?
    @client.send_packet! Serverbound::CloseWindow.new id.to_u16
    handle_closed
  end

  def handle_closed
    return if closed?
    self.closed = true

    if @client.window == self
      # Store the previous window ID to handle late packets
      @client.inventory.previous_window_id = self.id
      @client.window = @client.inventory
      @client.inventory.slots = @client.inventory.slots[0..8] + inventory + hotbar + @client.inventory.slots[45..45]
      @client.inventory.slots.each_with_index { |slot, i| slot.slot_number = i }
    end
  end

  # If true, this window is in sync with the server.
  def ready?
    !!(@slots && @cursor && !closed?)
  end

  def slots=(slots : Array(WindowSlot))
    # was_ready = ready?
    @slots = slots
    # TODO emit Ready event if ready? && !was_ready
  end

  def cursor=(cursor : WindowSlot)
    # was_ready = ready?
    @cursor = cursor
    # TODO emit Ready event if ready? && !was_ready
  end

  def slots : Array(WindowSlot)
    @slots ||= Array.new(46) { |i| WindowSlot.new i, Slot.new }
  end

  def cursor : WindowSlot
    @cursor || raise "Window is not ready"
  end

  # Slots specific to the window, ie. excluding inventory and hotbar.
  def content : Array(WindowSlot)
    slots[...@inventory_start]
  end

  def inventory : Array(WindowSlot)
    slots[@inventory_start...@inventory_start + 27]
  end

  def hotbar : Array(WindowSlot)
    slots[@inventory_start + 27...]
  end

  def main_hand : WindowSlot
    selection = @client.player.hotbar_selection
    # Clamp to valid hotbar range (0-8)
    selection = selection.clamp(0_u8, 8_u8)

    if selection < hotbar.size
      hotbar[selection]
    else
      # Default to first hotbar slot if selection is out of bounds
      hotbar[0]? || WindowSlot.new(0, Slot.new)
    end
  end

  # Hotbar starts at 0.
  def swap_hotbar(hotbar_nr, slot_number)
    # TODO do nothing if slot_number is hotbar_selection already
    # TODO change hotbar_selection if slot_number in hotbar
    send_click ClickWindow.swap_hotbar self, hotbar_nr, slot_number
    hotbar[hotbar_nr].swap_with slots[slot_number]
  end

  # Hotbar starts at 0.
  def swap_hotbar(hotbar_nr, slot : WindowSlot)
    swap_hotbar hotbar_nr, slot.slot_number
  end

  def swap_off_hand(slot_number)
    send_click ClickWindow.swap_off_hand self, slot_number
    @client.inventory.off_hand.swap_with slots[slot_number]
  end

  def swap_off_hand(slot : WindowSlot)
    swap_off_hand slot.slot_number
  end

  def drop(slot_number, stack_mode : StackMode)
    slot = slots[slot_number]
    if slot.slot_number < 0
      slot = cursor
      send_click ClickWindow.drop_cursor self, stack_mode
    else
      # TODO check that cursor is empty
      send_click ClickWindow.drop self, slot_number, stack_mode
    end
    case stack_mode
    when :single; slot.decrement
    when :full  ; slot.make_empty
    end
  end

  def drop(slot : WindowSlot, stack_mode : StackMode)
    drop slot.slot_number, stack_mode
  end

  def drop_cursor(stack_mode : StackMode)
    send_click ClickWindow.drop_cursor self, stack_mode
    case stack_mode
    when :single; cursor.decrement
    when :full  ; cursor.make_empty
    end
  end

  def click(slot_number, right = false, shift = false, double = false)
    send_click ClickWindow.click self, slot_number, right, shift, double
  end

  def click(slot : WindowSlot, right = false, shift = false, double = false)
    click slot.slot_number, right, shift, double
  end

  private def send_click(packet)
    @client.send_packet! packet
  end

  alias StackMode = Serverbound::ClickWindow::StackMode
  alias ClickWindow = Serverbound::ClickWindow

  def to_s(io)
    io.print "Window[#{id}: #{title}]"
  end
end

class Rosegold::PlayerWindow < Rosegold::Window
  property previous_window_id : UInt8? = nil

  def initialize(@client)
    @id = 0
    @title = Chat.new "Player Inventory"
    @type_id = 0
    @inventory_start = 9
  end

  # Handle late packets from a closed window by temporarily recreating and closing it
  def handle_late_packet(window_id : UInt8, slots : Array(WindowSlot)? = nil, slot : WindowSlot? = nil, cursor : WindowSlot? = nil, state_id : UInt32 = 0)
    Log.debug { "Handling late packet for previous window #{window_id}" }

    # Create a temporary window with the late data
    temp_window = Window.new(@client, window_id, Chat.new("Late Window"), 0_u32)

    # Apply the packet data to the temporary window
    if slots
      # SetContainerContent case
      temp_window.state_id = state_id
      temp_window.slots = slots
      temp_window.cursor = cursor if cursor
    elsif slot
      # SetSlot case - we need to initialize the window slots first
      temp_window.slots = Array.new(54) { |i| WindowSlot.new i, Slot.new }
      # Only set the slot if it's within bounds
      if slot.slot_number >= 0 && slot.slot_number < temp_window.slots.size
        temp_window.slots[slot.slot_number] = slot
      else
        Log.debug { "Ignoring SetSlot for out-of-bounds slot #{slot.slot_number}" }
        return # Don't proceed with handle_closed for invalid slots
      end
    end

    # Save current window
    current_window = @client.window
    @client.window = temp_window

    # Close the temporary window to properly sync inventory
    temp_window.handle_closed

    # Restore the current window
    @client.window = current_window
  end

  def crafting_result : WindowSlot
    slots[0]
  end

  def crafting_input : Array(WindowSlot)
    slots[1..4]
  end

  def helmet : WindowSlot
    slots[5]
  end

  def chestplate : WindowSlot
    slots[6]
  end

  def leggings : WindowSlot
    slots[7]
  end

  def boots : WindowSlot
    slots[8]
  end

  def inventory : Array(WindowSlot)
    # inventory isn't updated by server while other window is open
    return @client.window.inventory if @client.window != self
    slots[9..35]
  end

  def hotbar : Array(WindowSlot)
    # inventory isn't updated by server while other window is open
    return @client.window.hotbar if @client.window != self
    slots[36..44]
  end

  def off_hand : WindowSlot
    slots[45]
  end
end
