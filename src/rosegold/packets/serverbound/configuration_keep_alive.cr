require "../packet"

class Rosegold::Serverbound::ConfigurationKeepAlive < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    767_u32 => 0x04_u8, # MC 1.21
    771_u32 => 0x04_u8, # MC 1.21.6
  })

  property keep_alive_id : Int64

  def initialize(@keep_alive_id : Int64); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full keep_alive_id
    end.to_slice
  end
end
