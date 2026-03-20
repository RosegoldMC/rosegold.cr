require "./menu"

# Shared base for all container menus (everything except PlayerMenu).
# Provides slot access, state sync, close, and default validation/shift-click.
# Subclasses only need to define named accessors and override behavior that differs.
abstract class Rosegold::ContainerMenu < Rosegold::Menu
  getter container_size : Int32
  @container_slots_array : Array(Rosegold::Slot)

  def initialize(@client : Client, @id : UInt8, @title : Chat, @container_size : Int32)
    @container_slots_array = Array.new(@container_size) { Rosegold::Slot.new }
    super(@client, @client.player_inventory)
  end

  def menu_id : UInt8
    @id
  end

  def total_slots : Int32
    @container_size + 36
  end

  def player_inventory_start : Int32
    @container_size
  end

  def [](index : Int32) : Rosegold::Slot
    if index < @container_size
      @container_slots_array[index]
    elsif index < total_slots
      player_index = index - @container_size
      player_index < 27 ? @player_inventory[player_index + 9] : @player_inventory[player_index - 27]
    else
      raise ArgumentError.new("Invalid slot index #{index} for #{self.class.name}")
    end
  end

  def []=(index : Int32, slot : Rosegold::Slot)
    if index < @container_size
      @container_slots_array[index] = slot
    elsif index < total_slots
      player_index = index - @container_size
      if player_index < 27
        @player_inventory[player_index + 9] = slot
      else
        @player_inventory[player_index - 27] = slot
      end
    else
      raise ArgumentError.new("Invalid slot index #{index} for #{self.class.name}")
    end
  end

  def offhand_slot_index : Int32
    -1
  end

  def hotbar_slot_index(hotbar_nr : Int32) : Int32
    @container_size + 27 + hotbar_nr
  end

  def container_slots : Array(Rosegold::WindowSlot)
    @container_slots_array.map_with_index { |slot, i| Rosegold::WindowSlot.new(i, slot) }
  end

  def inventory_slots : Array(Rosegold::WindowSlot)
    Array(Rosegold::WindowSlot).new(27) { |i| Rosegold::WindowSlot.new(@container_size + i, @player_inventory[i + 9]) }
  end

  def hotbar_window_slots : Array(Rosegold::WindowSlot)
    Array(Rosegold::WindowSlot).new(9) { |i| Rosegold::WindowSlot.new(@container_size + 27 + i, @player_inventory[i]) }
  end

  def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    true
  end

  def may_pickup?(slot_index : Int32) : Bool
    true
  end

  def allow_modification?(slot_index : Int32) : Bool
    true
  end

  def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    get_max_stack_size(item_slot)
  end

  def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original = copy_slot(slot)

    if slot_index < @container_size
      move_item_stack_to(slot_index, @container_size, total_slots, true)
    else
      move_item_stack_to(slot_index, 0, @container_size, false)
    end

    return Rosegold::Slot.new if self[slot_index].count == original.count
    original
  end

  def close
    @client.send_packet!(Serverbound::CloseWindow.new(menu_id.to_u16))
    handle_close
  end

  def handle_close
    @client.container_menu = @client.inventory_menu
  end
end
