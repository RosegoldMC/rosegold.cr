require "../packet"

class Rosegold::Clientbound::SetCursorItem < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x59_u32,
    773_u32 => 0x5E_u32,
    774_u32 => 0x5E_u32,
    775_u32 => 0x60_u32,
    776_u32 => 0x60_u32,
  })

  property slot : Slot

  def initialize(@slot)
  end

  def self.read(packet)
    new Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write slot
    end.to_slice
  end

  def callback(client)
    menu = client.container_menu
    menu.update_slot(-1, slot, menu.state_id)
  end
end
