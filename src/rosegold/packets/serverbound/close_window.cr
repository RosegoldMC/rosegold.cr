require "../packet"

class Rosegold::Serverbound::CloseWindow < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x09_u8, # MC 1.18
    767_u32 => 0x0F_u8, # MC 1.21
    769_u32 => 0x0F_u8, # MC 1.21.4,
    771_u32 => 0x0F_u8, # MC 1.21.6,
    772_u32 => 0x12_u8, # MC 1.21.8,
  })

  property window_id : UInt16

  def initialize(@window_id : UInt16); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
    end.to_slice
  end
end
