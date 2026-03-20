require "../container_menu"

# Enchantment table menu — 2 slots: item(0), lapis(1).
class Rosegold::EnchantmentMenu < Rosegold::ContainerMenu
  def initialize(@client : Client, @id : UInt8, @title : Chat)
    super(@client, @id, @title, 2)
  end

  def item : Rosegold::Slot
    @container_slots_array[0]
  end

  def lapis : Rosegold::Slot
    @container_slots_array[1]
  end

  def may_place?(slot_index : Int32, item_slot : Rosegold::Slot) : Bool
    if slot_index == 1
      ItemConstants.lapis_lazuli?(item_slot.item_id_int)
    else
      true
    end
  end

  def get_slot_max_stack_size(slot_index : Int32, item_slot : Rosegold::Slot) : Int32
    slot_index == 0 ? 1 : super
  end

  def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original = copy_slot(slot)

    if slot_index < @container_size
      move_item_stack_to(slot_index, @container_size, total_slots, true)
    else
      if ItemConstants.lapis_lazuli?(slot.item_id_int)
        if !move_item_stack_to(slot_index, 1, 2, true)
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
      elsif !move_item_stack_to(slot_index, 0, 1, false)
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
