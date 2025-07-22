require "../packet"

class Rosegold::Serverbound::ChatMessage < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (changes between versions!)
  packet_ids({
    758_u32 => 0x03_u8, # MC 1.18
    767_u32 => 0x05_u8, # MC 1.21 - CHANGED!
    769_u32 => 0x05_u8, # MC 1.21.4,
    771_u32 => 0x05_u8, # MC 1.21.6,
  })

  property message : String

  def initialize(@message : String); end

  def self.read(io)
    self.new(io.read_var_string)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write message
    end.to_slice
  end
end
