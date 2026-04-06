require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::DisguisedChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x1D_u32, # MC 1.21.8
    774_u32 => 0x21_u32, # MC 1.21.11
    775_u32 => 0x21_u32, # MC 26.1
  })

  property \
    message : Rosegold::TextComponent,
    chat_type : UInt32,
    sender_name : Rosegold::TextComponent,
    target_name : Rosegold::TextComponent?

  def initialize(@message, @chat_type, @sender_name, @target_name); end

  def self.read(packet)
    message = packet.read_text_component
    chat_type = packet.read_var_int.to_u32
    sender_name = packet.read_text_component
    target_name = packet.read_bool ? packet.read_text_component : nil
    self.new(message, chat_type, sender_name, target_name)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      message.write(buffer)
      buffer.write chat_type
      sender_name.write(buffer)
      if target = target_name
        buffer.write true
        target.write(buffer)
      else
        buffer.write false
      end
    end.to_slice
  end

  def callback(client)
    Log.info { "[DISGUISED CHAT] #{sender_name}: #{message}" }
  end
end
