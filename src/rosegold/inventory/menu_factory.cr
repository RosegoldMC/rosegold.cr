require "./menu"
require "./menus/*"

module Rosegold::MenuFactory
  # Create the correct Menu subclass from OpenScreen packet type_id.
  # IDs from MenuType.java declaration order (MC 1.21.8+).
  def self.create(client : Client, container_id : UInt8, title : Chat, type_id : UInt32) : Menu
    # Menu type IDs are identical for protocols 772 and 774. Verify when adding new versions.
    case type_id
    when  0 then ChestMenu.new(client, container_id, title, rows: 1)              # GENERIC_9x1
    when  1 then ChestMenu.new(client, container_id, title, rows: 2)              # GENERIC_9x2
    when  2 then ChestMenu.new(client, container_id, title, rows: 3)              # GENERIC_9x3
    when  3 then ChestMenu.new(client, container_id, title, rows: 4)              # GENERIC_9x4
    when  4 then ChestMenu.new(client, container_id, title, rows: 5)              # GENERIC_9x5
    when  5 then ChestMenu.new(client, container_id, title, rows: 6)              # GENERIC_9x6
    when  6 then GenericMenu.new(client, container_id, title, container_size: 9)  # GENERIC_3x3
    when  7 then GenericMenu.new(client, container_id, title, container_size: 9)  # CRAFTER_3x3
    when  8 then AnvilMenu.new(client, container_id, title)                       # ANVIL
    when  9 then GenericMenu.new(client, container_id, title, container_size: 1)  # BEACON
    when 10 then FurnaceMenu.new(client, container_id, title)                     # BLAST_FURNACE
    when 11 then BrewingStandMenu.new(client, container_id, title)                # BREWING_STAND
    when 12 then CraftingMenu.new(client, container_id, title)                    # CRAFTING
    when 13 then EnchantmentMenu.new(client, container_id, title)                 # ENCHANTMENT
    when 14 then FurnaceMenu.new(client, container_id, title)                     # FURNACE
    when 15 then GenericMenu.new(client, container_id, title, container_size: 3)  # GRINDSTONE
    when 16 then HopperMenu.new(client, container_id, title)                      # HOPPER
    when 17 then GenericMenu.new(client, container_id, title, container_size: 1)  # LECTERN
    when 18 then GenericMenu.new(client, container_id, title, container_size: 4)  # LOOM
    when 19 then MerchantMenu.new(client, container_id, title)                    # MERCHANT
    when 20 then ChestMenu.new(client, container_id, title, rows: 3)              # SHULKER_BOX
    when 21 then GenericMenu.new(client, container_id, title, container_size: 4)  # SMITHING
    when 22 then FurnaceMenu.new(client, container_id, title)                     # SMOKER
    when 23 then GenericMenu.new(client, container_id, title, container_size: 3)  # CARTOGRAPHY_TABLE
    when 24 then GenericMenu.new(client, container_id, title, container_size: 2)  # STONECUTTER
    else         GenericMenu.new(client, container_id, title, container_size: 27) # Unknown fallback
    end
  end

  # Open a new container menu, closing any existing one first.
  def self.open(client : Client, container_id : UInt8, title : Chat, type_id : UInt32) : Menu
    current = client.container_menu
    if current != client.inventory_menu
      current.handle_close
    end

    menu = create(client, container_id, title, type_id)
    client.container_menu = menu
    menu
  end
end
