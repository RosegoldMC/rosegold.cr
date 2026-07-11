class Rosegold::Clientbound::SetPlayerInventory < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x65_u32, # MC 1.21.8
    773_u32 => 0x6A_u32, # MC 1.21.9
    774_u32 => 0x6A_u32, # MC 1.21.11
    775_u32 => 0x6C_u32, # MC 26.1
    776_u32 => 0x6C_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

  property \
    raw_slot : Int32,
    slot : Slot

  def initialize(@raw_slot, @slot)
  end

  def self.read(packet)
    raw_slot = packet.read_var_int.to_i32
    new raw_slot, Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write raw_slot
      buffer.write slot
    end.to_slice
  end

  # Wire index is the raw player-Inventory index (Java `Inventory` class
  # layout: hotbar 0-8, main 9-35, armor 36-39 boots..helmet, offhand 40),
  # which does not match PlayerMenu's 46-slot window layout.
  def self.menu_index_for(raw_slot : Int32) : Int32?
    case raw_slot
    when 0..8  then PlayerMenu::HOTBAR_START + raw_slot
    when 9..35 then raw_slot
    when 36    then PlayerMenu::BOOTS_SLOT
    when 37    then PlayerMenu::LEGGINGS_SLOT
    when 38    then PlayerMenu::CHESTPLATE_SLOT
    when 39    then PlayerMenu::HELMET_SLOT
    when 40    then PlayerMenu::OFF_HAND
    else            nil
    end
  end

  def callback(client)
    menu_index = self.class.menu_index_for(raw_slot)
    if menu_index
      client.inventory_menu[menu_index] = slot
    else
      Log.debug { "Received player inventory update for unmapped raw slot #{raw_slot} (body/saddle equipment). Ignoring." }
    end
  end
end
