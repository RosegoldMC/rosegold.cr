require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::SystemChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x72_u8, # MC 1.21.8 - System Chat Message
  })

  property message : Rosegold::TextComponent
  property? overlay : Bool

  def initialize(@message, @overlay = false); end

  def self.read(packet)
    # Read Content (Text Component) - NBT format for MC 1.21.8
    begin
      message = packet.read_text_component
    rescue ex
      # Fallback if NBT reading fails
      Log.warn { "Failed to parse system chat content as NBT: #{ex.message}, trying as string" }
      content_string = packet.read_var_string rescue "System message"
      message = TextComponent.new(content_string)
    end

    # Read Overlay (Boolean)
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
