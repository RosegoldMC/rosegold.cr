require "../packet"

# Direct player-inventory slot update (added in 1.21.5). Vanilla servers only
# emit this when returning items from temporary slots on container close; it
# uses Inventory slot indices (0-8 hotbar, 9-35 main, 36-39 armor, 40 offhand),
# not menu-window slot indices, and carries no state id. Decoded so it doesn't
# fall back to RawPacket, but applied as a no-op (matches azalea-client).
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
    Log.debug { "SetPlayerInventory slot=#{slot_index} item=#{slot_data} (no-op)" }
  end
end
