require "./menu"

# User-facing handle for interacting with an open container.
# Wraps a Menu and provides intent-level operations (withdraw, deposit)
# as well as item-level operations (pickup, put_down, move, swap).
# Auto-closes via ensure when used with a block.
class Rosegold::ContainerHandle
  getter menu : Menu
  private getter client : Client

  def initialize(@client, @menu)
  end

  # --- Item-level operations ---

  # Pick up items from a slot into the cursor.
  # Uses left-click for full stack, right-click for half.
  def pickup(slot : Int32, count : Int32 = Int32::MAX)
    current = menu[slot]
    return if current.empty?

    if count >= current.count.to_i
      menu.send_click(slot, 0, :click)
    else
      # Right-click picks up half; if that's too many, we put some back
      menu.send_click(slot, 1, :click)
      # If we picked up more than needed, put extras back
      picked = menu.cursor.count.to_i
      excess = picked - count
      if excess > 0
        excess.times do
          menu.send_click(slot, 1, :click) if !menu.cursor.empty?
        end
      end
    end
  end

  # Put down items from cursor into a slot.
  # Left-click places all, right-click places one.
  def put_down(slot : Int32, count : Int32 = Int32::MAX)
    return if menu.cursor.empty?

    if count >= menu.cursor.count.to_i
      menu.send_click(slot, 0, :click)
    else
      count.times do
        break if menu.cursor.empty?
        menu.send_click(slot, 1, :click)
      end
    end
  end

  # Shift-click a slot (moves items between container and player inventory).
  def quick_move(slot : Int32)
    menu.send_click(slot, 0, :shift)
  end

  # Swap a slot with a hotbar slot (number keys 1-9).
  def swap_with_hotbar(slot : Int32, hotbar_slot : Int32)
    menu.swap_hotbar(hotbar_slot, slot)
  end

  # Swap a slot with the offhand (F key).
  def swap_with_offhand(slot : Int32)
    menu.send_click(slot, 40, :swap)
  end

  # Drop items from a slot.
  def drop(slot : Int32, full_stack : Bool = false)
    button = full_stack ? 1 : 0
    menu.send_click(slot, button, :drop)
  end

  # --- Intent-level operations ---

  # Transfer items from container to player inventory via shift-click.
  # Returns the number of items actually transferred.
  def withdraw(spec, count : Int32 = Int32::MAX) : Int32
    transferred = 0

    loop do
      break if transferred >= count

      source = menu.container_slots.find(&.matches?(spec))
      break unless source

      before = count_in_player(spec)
      menu.send_click(source.slot_number, 0, :shift)
      client.wait_tick
      after = count_in_player(spec)

      moved = after - before
      transferred += moved
      break if moved == 0
    end

    transferred
  end

  # Transfer items from player inventory to container via shift-click.
  # Returns the number of items actually transferred.
  def deposit(spec, count : Int32 = Int32::MAX) : Int32
    transferred = 0

    loop do
      break if transferred >= count

      source = menu.player_window_slots.find(&.matches?(spec))
      break unless source

      before = count_in_player(spec)
      menu.send_click(source.slot_number, 0, :shift)
      client.wait_tick
      after = count_in_player(spec)

      moved = before - after
      transferred += moved
      break if moved == 0
    end

    transferred
  end

  # Find the first slot matching spec in the container.
  def find_in_container(spec) : WindowSlot?
    menu.container_slots.find(&.matches?(spec))
  end

  # Find the first slot matching spec in the player inventory.
  def find_in_inventory(spec) : WindowSlot?
    menu.player_window_slots.find(&.matches?(spec))
  end

  # Count matching items in the container.
  def count_in_container(spec) : Int32
    menu.container_slots.select(&.matches?(spec)).sum(&.count.to_i32)
  end

  # Count matching items in the player inventory.
  def count_in_player(spec) : Int32
    menu.player_window_slots
      .select(&.matches?(spec))
      .sum(&.count.to_i32)
  end

  # --- Typed menu access ---

  # Returns the menu as a specific type, or nil if it doesn't match.
  def as_chest : ChestMenu?
    menu.as?(ChestMenu)
  end

  def as_crafting : CraftingMenu?
    menu.as?(CraftingMenu)
  end

  def as_furnace : FurnaceMenu?
    menu.as?(FurnaceMenu)
  end

  def as_anvil : AnvilMenu?
    menu.as?(AnvilMenu)
  end

  def as_brewing_stand : BrewingStandMenu?
    menu.as?(BrewingStandMenu)
  end

  def as_enchantment : EnchantmentMenu?
    menu.as?(EnchantmentMenu)
  end

  def as_hopper : HopperMenu?
    menu.as?(HopperMenu)
  end

  def as_merchant : MerchantMenu?
    menu.as?(MerchantMenu)
  end

  # --- Lifecycle ---

  def close
    menu.close
  end
end
