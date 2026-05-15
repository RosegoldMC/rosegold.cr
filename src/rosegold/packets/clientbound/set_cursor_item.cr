require "../packet"

# Authoritative cursor sync introduced in 1.21.5. The server emits this when the
# carried item changes server-side (e.g. divergence between predicted and actual
# carried hash after a click). Replaces the legacy `SetSlot(window=-1, slot=-1)`
# form, which no longer fires on 1.21.5+ vanilla.
class Rosegold::Clientbound::SetCursorItem < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x59_u32, # MC 1.21.8
    774_u32 => 0x5E_u32, # MC 1.21.11
    775_u32 => 0x60_u32, # MC 26.1
  })

  property carried_item : Slot

  def initialize(@carried_item)
  end

  def self.read(packet)
    new Slot.read(packet)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write carried_item
    end.to_slice
  end

  def callback(client)
    Log.debug { "SetCursorItem: #{carried_item}" }
    menu = client.container_menu
    menu.update_slot(-1, carried_item.as(Rosegold::Slot), menu.state_id)
  end
end
