# Slot accessor methods raise an error if the window is not ready.
# Note that slots are still available even after the window has been closed.
class Rosegold::Window
  getter client : Client
  getter id : UInt32
  getter title : Chat
  # nil for PlayerWindow
  getter type_id : UInt32?
  # inventory+hotbar are at the end in all windows except the player inventory
  @inventory_start : Int32 = -36
  property state_id : UInt32 = 0
  # nil if window is not ready
  @slots : Array(Slot)?
  # nil if window is not ready
  @cursor : Slot?
  # If true, this window will never become ready in the future.
  property? closed : Bool = false

  def initialize(@client, @id, @title, @type_id); end

  def close
    closed = true
    # TODO emit event
  end

  # If true, this window is in sync with the server.
  def ready?
    !!(@slots && @cursor && !closed?)
  end

  def slots : Array(Slot)
    @slots || raise "Window is not ready"
  end

  def cursor : Slot
    @cursor || raise "Window is not ready"
  end

  def slots=(slots : Array(Slot))
    # was_ready = ready?
    @slots = slots
    # TODO emit Ready if ready? && !was_ready
  end

  def cursor=(cursor : Slot)
    # was_ready = ready?
    @cursor = cursor
    # TODO emit Ready if ready? && !was_ready
  end

  # Slots specific to the window, ie. excluding inventory and hotbar.
  def content : Array(Slot)
    slots[...@inventory_start]
  end

  def inventory : Array(Slot)
    slots[@inventory_start...@inventory_start + 27]
  end

  def hotbar : Array(Slot)
    slots[@inventory_start + 27...@inventory_start + 36]
  end

  def main_hand : Slot
    hotbar[client.player.hotbar_selection]
  end
end

class Rosegold::PlayerWindow < Rosegold::Window
  def initialize(@client)
    @id = 0
    @title = Chat.new "Player Inventory"
    @type_id = nil
    @inventory_start = 9
  end

  def crafting_result : Slot
    slots[0]
  end

  def crafting_input : Array(Slot)
    slots[1..4]
  end

  def helmet : Slot
    slots[5]
  end

  def chestplate : Slot
    slots[6]
  end

  def leggings : Slot
    slots[7]
  end

  def boots : Slot
    slots[8]
  end

  def off_hand : Slot
    slots[45]
  end
end
