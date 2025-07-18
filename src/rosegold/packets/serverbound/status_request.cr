require "../packet"

class Rosegold::Serverbound::StatusRequest < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (same across all versions)
  packet_ids({
    758_u32 => 0x00_u8, # MC 1.18
    767_u32 => 0x00_u8, # MC 1.21
    771_u32 => 0x00_u8, # MC 1.21.6
  })

  class_getter state = Rosegold::ProtocolState::STATUS

  def self.read(io)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID (though same for all versions)
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end
end
