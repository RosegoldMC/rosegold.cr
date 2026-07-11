require "../packet"

class Rosegold::Clientbound::CodeOfConduct < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    773_u32 => 0x13_u32, # MC 1.21.9
    774_u32 => 0x13_u32, # MC 1.21.11
    775_u32 => 0x13_u32, # MC 26.1
    776_u32 => 0x13_u32, # MC 26.2
  })

  property text : String

  def initialize(@text); end

  def self.read(packet)
    self.new(packet.read_var_string)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write text
    end.to_slice
  end

  def callback(client)
    client.send_packet! Serverbound::AcceptCodeOfConduct.new
  end
end
