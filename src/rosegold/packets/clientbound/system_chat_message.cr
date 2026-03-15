require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::SystemChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x72_u32, # MC 1.21.8
    774_u32 => 0x77_u32, # MC 1.21.11
  })

  property message : Rosegold::TextComponent
  property? overlay : Bool

  def initialize(@message, @overlay = false); end

  def self.read(packet)
    message = packet.read_text_component
    overlay = packet.read_bool
    self.new(message, overlay)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ uses NBT text component format
      message.write(buffer)
      buffer.write @overlay
    end.to_slice
  end

  def callback(client)
    if overlay?
      Log.info { "[ACTION BAR] " + message.to_s }
    else
      Log.info { "[SYSTEM CHAT] " + message.to_s }
    end
  end
end
