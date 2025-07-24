require "../../models/chat"
require "../packet"
require "../../../minecraft/nbt"

class Rosegold::Clientbound::ChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for System Chat Message
  packet_ids({
    772_u32 => 0x72_u8, # MC 1.21.8 - System Chat Message
  })

  property \
    message : Rosegold::Chat,
    overlay : Bool

  def initialize(@message, @overlay = false); end

  def self.read(packet)
    # For protocol 772+ (MC 1.21.8), the format is:
    # - NBT Text Component (not JSON)
    # - Boolean overlay flag
    
    # Read the NBT text component
    nbt_tag = Minecraft::NBT::Tag.read(packet) { |tag_type| }
    
    # Try to convert NBT to a Chat object
    # For now, we'll create a simple text chat from the NBT data
    chat_message = case nbt_tag
    when Minecraft::NBT::StringTag
      Rosegold::Chat.new(nbt_tag.value)
    when Minecraft::NBT::CompoundTag
      # Try to extract text from compound tag
      text_tag = nbt_tag["text"]?
      text_value = if text_tag.is_a?(Minecraft::NBT::StringTag)
                     text_tag.value
                   else
                     # Fallback: try to extract any string content
                     nbt_tag.value.values.find { |v| v.is_a?(Minecraft::NBT::StringTag) }
                       .try { |tag| tag.as(Minecraft::NBT::StringTag).value } || 
                     "Failed to extract text from NBT: #{nbt_tag.to_s}"
                   end
      Rosegold::Chat.new(text_value)
    else
      Rosegold::Chat.new(nbt_tag.to_s)
    end
    
    overlay = packet.read_bool
    
    self.new(chat_message, overlay)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      
      # For protocol 772+ (MC 1.21.8), write NBT text component
      # Due to NBT library issues with compound tags, let's try a simple string tag
      # which should be acceptable for basic text messages
      text_content = message.text || message.to_s
      
      # Write NBT string tag: tag_type (8) + empty name + string data
      buffer.write 8_u8  # String tag type
      buffer.write 0_u16  # Empty name (length 0)
      buffer.write text_content.bytesize.to_u16  # String length
      buffer.print text_content  # String value
      
      buffer.write overlay
    end.to_slice
  end

  def callback(client)
    Log.info { "[CHAT] " + message.to_s }
  end
end
