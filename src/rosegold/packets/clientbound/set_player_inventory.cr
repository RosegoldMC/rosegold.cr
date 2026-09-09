require "../packet"

class Rosegold::Clientbound::SetPlayerInventory < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x65_u32,
    773_u32 => 0x6A_u32,
    774_u32 => 0x6A_u32,
    775_u32 => 0x6C_u32,
    776_u32 => 0x6C_u32,
  })

  property \
    raw_slot : Int32,
    slot : Slot

  def initialize(@raw_slot, @slot)
  end

  def self.read(packet)
    new packet.read_var_int.to_i32, Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write raw_slot
      buffer.write slot
    end.to_slice
  end

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
    if menu_index = self.class.menu_index_for(raw_slot)
      inventory = client.inventory_menu
      inventory.update_slot(menu_index, slot, inventory.state_id)
    end
  end
end
