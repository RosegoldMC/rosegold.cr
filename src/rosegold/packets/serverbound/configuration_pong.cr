require "../packet"

class Rosegold::Serverbound::ConfigurationPong < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    772_u32 => 0x05_u32, # MC 1.21.8
    773_u32 => 0x05_u32, # MC 1.21.9
    774_u32 => 0x05_u32, # MC 1.21.11
    775_u32 => 0x05_u32, # MC 26.1
    776_u32 => 0x05_u32, # MC 26.2
  })

  property ping_id : Int32

  def initialize(@ping_id : Int32); end

  def self.read(packet)
    self.new(packet.read_int)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full ping_id
    end.to_slice
  end
end
