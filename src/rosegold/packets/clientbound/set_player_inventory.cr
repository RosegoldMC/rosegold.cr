require "../packet"

# Direct player-inventory slot update (added in 1.21.5). Vanilla servers
# emit this when returning items from temporary slots on container close —
# e.g. leftover crafting-grid items get added back to the player inventory,
# routing through Inventory#setItem which broadcasts this packet for each
# affected slot. Carries no state id.
#
# Slot indices follow vanilla's Inventory layout (Inventory.java#setItem +
# EQUIPMENT_SLOT_MAPPING): 0-8 hotbar, 9-35 main inventory, 36 FEET,
# 37 LEGS, 38 CHEST, 39 HEAD, 40 OFFHAND. (41 BODY, 42 SADDLE are mount
# armor and aren't reachable through the player menu.)
class Rosegold::Clientbound::SetPlayerInventory < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x65_u32, # MC 1.21.8
    774_u32 => 0x6A_u32, # MC 1.21.11
    775_u32 => 0x6C_u32, # MC 26.1
  })

  property slot_index : UInt32
  property slot_data : Slot

  def initialize(@slot_index, @slot_data)
  end

  def self.read(packet)
    new packet.read_var_int, Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write slot_index
      buffer.write slot_data
    end.to_slice
  end

  def callback(client)
    menu_index = self.class.player_menu_slot(slot_index)
    if menu_index.nil?
      Log.debug { "SetPlayerInventory: ignoring unsupported slot #{slot_index}" }
      return
    end

    inventory = client.inventory_menu
    Log.debug { "SetPlayerInventory net=#{slot_index} menu=#{menu_index} item=#{slot_data}" }
    inventory.update_slot(menu_index, slot_data.as(Rosegold::Slot), inventory.state_id)
  end

  # Translates a vanilla Inventory slot index to a PlayerMenu slot index.
  # Returns nil for mount-armor slots (BODY/SADDLE) which aren't represented
  # in the player menu.
  def self.player_menu_slot(slot_index : UInt32) : Int32?
    case slot_index
    when 0_u32..8_u32  then SlotOffsets::PlayerSlots::HOTBAR_START + slot_index.to_i32
    when 9_u32..35_u32 then slot_index.to_i32
    when 36_u32        then SlotOffsets::PlayerSlots::BOOTS_SLOT
    when 37_u32        then SlotOffsets::PlayerSlots::LEGGINGS_SLOT
    when 38_u32        then SlotOffsets::PlayerSlots::CHESTPLATE_SLOT
    when 39_u32        then SlotOffsets::PlayerSlots::HELMET_SLOT
    when 40_u32        then SlotOffsets::PlayerSlots::OFF_HAND
    else                    nil
    end
  end
end
