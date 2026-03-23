require "../container_menu"

# Crafting table menu — 10 slots: result(0), grid(1-9).
class Rosegold::CraftingMenu < Rosegold::ContainerMenu
  def initialize(@client : Client, @id : UInt8, @title : Chat)
    super(@client, @id, @title, 10)
  end

  def result : Rosegold::Slot
    @container_slots_array[0]
  end

  def grid : Array(Rosegold::Slot)
    @container_slots_array[1..9]
  end

  def crafting_grid_range : Range(Int32, Int32)
    1..9
  end

  def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    slot_index != 0
  end

  def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original = copy_slot(slot)

    if slot_index == 0
      move_item_stack_to(slot_index, @container_size, total_slots, true)
    elsif slot_index < @container_size
      move_item_stack_to(slot_index, @container_size, total_slots, false)
    else
      if !move_item_stack_to(slot_index, 1, @container_size, false)
        inv_start = @container_size
        inv_end = @container_size + 27
        hotbar_start = @container_size + 27
        hotbar_end = total_slots
        if slot_index < hotbar_start
          move_item_stack_to(slot_index, hotbar_start, hotbar_end, false)
        else
          move_item_stack_to(slot_index, inv_start, inv_end, false)
        end
      end
    end

    return Rosegold::Slot.new if self[slot_index].count == original.count
    original
  end
end
