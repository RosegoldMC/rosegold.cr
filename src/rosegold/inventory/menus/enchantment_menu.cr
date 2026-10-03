require "../container_menu"

# Enchantment table menu — 2 slots: item(0), lapis(1).
class Rosegold::EnchantmentMenu < Rosegold::ContainerMenu
  @offers : StaticArray(EnchantmentOffer?, 3) = StaticArray(EnchantmentOffer?, 3).new { nil }
  @enchanting = false

  def initialize(@client : Client, @id : UInt8, @title : Chat)
    super(@client, @id, @title, 2)
  end

  def item : Rosegold::Slot
    @container_slots_array[0]
  end

  def lapis : Rosegold::Slot
    @container_slots_array[1]
  end

  # Cached server offers, updated one property at a time rather than atomically.
  # Names are display clues only; custom names remain namespaced and unknown
  # IDs remain unnamed. Disabled or incomplete offers are nil.
  def offers : StaticArray(EnchantmentOffer?, 3)
    3.times do |index|
      required_level = properties[index.to_i16]?
      next unless required_level
      if required_level <= 0
        @offers[index] = nil
        next
      end

      clue_id = properties[(index + 4).to_i16]?
      clue_level = properties[(index + 7).to_i16]?.try(&.to_i)
      unless clue_id && clue_id >= 0 && clue_level && clue_level > 0
        @offers[index] = nil
        next
      end
      @offers[index] = EnchantmentOffer.new(
        index,
        required_level.to_i,
        index + 1,
        index + 1,
        clue_id ? enchantment_name(clue_id) : nil,
        clue_level
      )
    end
    @offers
  end

  # Selects one currently advertised offer and waits for the enchanted input
  # stack plus the server's survival resource updates.
  def enchant(option : Int32, timeout : Time::Span = 5.seconds) : Rosegold::Slot
    raise "An enchantment operation is already in progress" if @enchanting

    @enchanting = true
    begin
      Enchanting.new(@client, self).enchant(option, timeout)
    ensure
      @enchanting = false
    end
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

  private def enchantment_name(id : Int16) : String?
    return nil if id < 0
    entry = @client.registries["minecraft:enchantment"]?.try(&.entries[id.to_i]?)
    return nil unless entry
    name = entry[:id]
    name.starts_with?("minecraft:") ? name["minecraft:".size..] : name
  end
end
