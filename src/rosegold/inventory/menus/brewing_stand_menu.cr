require "../container_menu"

# Brewing stand menu — 5 slots: bottles(0-2), ingredient(3), fuel(4).
class Rosegold::BrewingStandMenu < Rosegold::ContainerMenu
  def initialize(@client : Client, @id : UInt8, @title : Chat)
    super(@client, @id, @title, 5)
  end

  def bottles : Array(Rosegold::Slot)
    @container_slots_array[0..2]
  end

  def ingredient : Rosegold::Slot
    @container_slots_array[3]
  end

  def fuel : Rosegold::Slot
    @container_slots_array[4]
  end

  # Vanilla restrictions: bottles(0-2) accept glass_bottle/potion/splash_potion/lingering_potion,
  # fuel(4) accepts only blaze_powder, ingredient(3) accepts anything.
  # Keeping default `true` for simplicity since we don't have a full potion item check.

  def quick_move_stack(slot_index : Int32) : Rosegold::Slot
    slot = self[slot_index]
    return Rosegold::Slot.new if slot.empty?

    original = copy_slot(slot)

    if slot_index < @container_size
      # Container slot → player inventory (vanilla uses reverse=true for ALL container slots)
      move_item_stack_to(slot_index, @container_size, total_slots, true)
    else
      # Player inventory → container: try fuel, then ingredient, then bottles
      if slot.name == "blaze_powder"
        if !move_item_stack_to(slot_index, 4, 5, false)
          if !move_item_stack_to(slot_index, 3, 4, false)
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
      elsif !move_item_stack_to(slot_index, 3, 4, false)
        if !move_item_stack_to(slot_index, 0, 3, false)
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
    end

    return Rosegold::Slot.new if self[slot_index].count == original.count
    original
  end
end
