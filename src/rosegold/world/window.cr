# Slot accessor methods raise an error if the window is not ready.
# Note that slots are still available even after the window has been closed.
class Rosegold::Window
  @client : Client

  getter id : UInt32

  getter title : Chat

  # `nil` for PlayerWindow
  getter type_id : UInt32?

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
    closed = true
    @client.send_packet! Serverbound::CloseWindow.new id.to_u16
    # TODO emit Closed event
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
    @slots || raise "Window is not ready"
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
    slots[@inventory_start + 27...@inventory_start + 36]
  end

  def main_hand : WindowSlot
    hotbar[@client.player.hotbar_selection]
  end
end

class Rosegold::PlayerWindow < Rosegold::Window
  def initialize(@client)
    @id = 0
    @title = Chat.new "Player Inventory"
    @type_id = nil
    @inventory_start = 9
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

  def off_hand : WindowSlot
    slots[45]
  end
end

class Rosegold::WindowSlot < Rosegold::Slot
  getter slot_nr : Int32

  def initialize(@slot_nr, slot)
    super slot.item_id_int, slot.count, slot.nbt
  end
end
