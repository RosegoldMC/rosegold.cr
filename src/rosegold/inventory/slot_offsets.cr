# Centralized slot offset calculations for inventory systems
# This module provides consistent offset calculations for different menu types
module Rosegold::SlotOffsets
  # Constants for player inventory structure
  HOTBAR_SIZE           =  9
  MAIN_INVENTORY_SIZE   = 27
  PLAYER_INVENTORY_SIZE = MAIN_INVENTORY_SIZE + HOTBAR_SIZE

  # Player inventory menu slot indices (InventoryMenu layout - 46 slots total)
  module PlayerSlots
    # Player inventory menu layout (46 slots total)
    CRAFTING_RESULT =  0
    CRAFTING_START  =  1
    CRAFTING_END    =  4
    ARMOR_START     =  5
    ARMOR_END       =  8
    MAIN_START      =  9
    MAIN_END        = 35
    HOTBAR_START    = 36
    HOTBAR_END      = 44
    OFF_HAND        = 45

    # Specific armor slots
    HELMET_SLOT     = 5
    CHESTPLATE_SLOT = 6
    LEGGINGS_SLOT   = 7
    BOOTS_SLOT      = 8

    TOTAL_SLOTS = 46
  end

  # Network protocol player inventory order: [main(0-26), hotbar(27-35)]
  # ContainerMenu treats network slots as: container_slots + [network_main + network_hotbar]
  module ContainerMenuOffsets
    # Get the absolute slot index for a hotbar slot in a container menu
    def self.hotbar_slot_index(container_size : Int32, hotbar_nr : Int32) : Int32
      # In container menu: container_slots + main_inventory(27) + hotbar_slot
      container_size + MAIN_INVENTORY_SIZE + hotbar_nr
    end

    # Get the absolute slot index for offhand in a container menu
    def self.offhand_slot_index(container_size : Int32) : Int32
      # Offhand is not part of the container menu - it's only accessible in InventoryMenu
      # Return invalid index to indicate it's not available
      -1
    end

    # Get the start index for main inventory slots in a container menu
    def self.main_inventory_start_index(container_size : Int32) : Int32
      container_size
    end

    # Get the start index for hotbar slots in a container menu
    def self.hotbar_start_index(container_size : Int32) : Int32
      container_size + MAIN_INVENTORY_SIZE
    end
  end

  # InventoryMenu slots: [crafting_result(0), crafting(1-4), armor(5-8), main(9-35), hotbar(36-44), offhand(45)]
  module InventoryMenuOffsets
    # Get the absolute slot index for a hotbar slot in inventory menu
    def self.hotbar_slot_index(hotbar_nr : Int32) : Int32
      PlayerSlots::HOTBAR_START + hotbar_nr
    end

    # Get the absolute slot index for offhand in inventory menu
    def self.offhand_slot_index : Int32
      PlayerSlots::OFF_HAND
    end

    # Get the start index for main inventory slots in inventory menu
    def self.main_inventory_start_index : Int32
      PlayerSlots::MAIN_START
    end

    # Get the start index for hotbar slots in inventory menu
    def self.hotbar_start_index : Int32
      PlayerSlots::HOTBAR_START
    end
  end

  # Player inventory internal structure: [hotbar(0-8), main(9-35)]
  # This is how PlayerInventory stores items internally
  module PlayerInventoryOffsets
    # Convert from main inventory index (0-26) to PlayerInventory index (9-35)
    def self.main_inventory_to_internal(main_index : Int32) : Int32
      HOTBAR_SIZE + main_index
    end

    # Convert from hotbar index (0-8) to PlayerInventory index (0-8)
    def self.hotbar_to_internal(hotbar_index : Int32) : Int32
      hotbar_index
    end

    # Convert from PlayerInventory index to main inventory index
    def self.internal_to_main_inventory(internal_index : Int32) : Int32?
      if internal_index >= HOTBAR_SIZE && internal_index < PLAYER_INVENTORY_SIZE
        internal_index - HOTBAR_SIZE
      else
        nil
      end
    end

    # Convert from PlayerInventory index to hotbar index
    def self.internal_to_hotbar(internal_index : Int32) : Int32?
      if internal_index >= 0 && internal_index < HOTBAR_SIZE
        internal_index
      else
        nil
      end
    end
  end

  # Network protocol slot ordering utilities
  module NetworkProtocolOffsets
    # Convert network slot index to PlayerInventory internal index
    def self.network_to_internal(network_index : Int32) : Int32
      if network_index < MAIN_INVENTORY_SIZE
        # Network main inventory (0-26) → PlayerInventory main (9-35)
        HOTBAR_SIZE + network_index
      else
        # Network hotbar (27-35) → PlayerInventory hotbar (0-8)
        network_index - MAIN_INVENTORY_SIZE
      end
    end

    # Convert PlayerInventory internal index to network slot index
    def self.internal_to_network(internal_index : Int32) : Int32
      if internal_index < HOTBAR_SIZE
        # PlayerInventory hotbar (0-8) → Network hotbar (27-35)
        MAIN_INVENTORY_SIZE + internal_index
      else
        # PlayerInventory main (9-35) → Network main (0-26)
        internal_index - HOTBAR_SIZE
      end
    end
  end
end
