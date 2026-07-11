require "../packet"

class Rosegold::Serverbound::AcceptCodeOfConduct < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    773_u32 => 0x09_u32, # MC 1.21.9
    774_u32 => 0x09_u32, # MC 1.21.11
    775_u32 => 0x09_u32, # MC 26.1
    776_u32 => 0x09_u32, # MC 26.2
  })

  def initialize; end

  def self.read(packet)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end
end
