class Rosegold::Clientbound::SetCursorItem < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x59_u32, # MC 1.21.8
    773_u32 => 0x5E_u32, # MC 1.21.9
    774_u32 => 0x5E_u32, # MC 1.21.11
    775_u32 => 0x60_u32, # MC 26.1
    776_u32 => 0x60_u32, # MC 26.2
  })
  class_getter state = ProtocolState::PLAY

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
    client.container_menu.cursor = slot
  end
end
