require "../packet"

class Rosegold::Clientbound::StatusPong < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs (same across all versions)
  packet_ids({
    758_u32 => 0x01_u8, # MC 1.18
    767_u32 => 0x01_u8, # MC 1.21
    771_u32 => 0x01_u8, # MC 1.21.6
    772_u32 => 0x01_u8, # MC 1.21.8
  })
  class_getter state = Rosegold::ProtocolState::STATUS

  property ping_id : Int64

  def initialize(@ping_id); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full ping_id
    end.to_slice
  end
end
