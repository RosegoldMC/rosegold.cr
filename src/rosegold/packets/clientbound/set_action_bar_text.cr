require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::SetActionBarText < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x50_u32, # MC 1.21.8
    774_u32 => 0x55_u32, # MC 1.21.11
    775_u32 => 0x57_u32, # MC 26.1
  })

  property text : Rosegold::TextComponent

  def initialize(@text); end

  def self.read(packet)
    self.new(packet.read_text_component)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      text.write(buffer)
    end.to_slice
  end

  def callback(client)
    Log.debug { "[ACTION BAR] " + text.to_s }
  end
end
