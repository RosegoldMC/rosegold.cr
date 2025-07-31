require "../../models/chat"
require "../packet"

class Rosegold::Clientbound::SystemChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for System Chat Message
  packet_ids({
    772_u32 => 0x72_u8, # MC 1.21.8 - System Chat Message
  })

  property message : Rosegold::Chat
  property? overlay : Bool

  def initialize(@message, @overlay = false); end

  def self.read(packet)
    # Read Content (Text Component) - NBT format for MC 1.21.8
    begin
      content_nbt = packet.read_nbt_unamed
      message = nbt_to_chat(content_nbt)
    rescue
      # Fallback if NBT reading fails
      Log.warn { "Failed to parse system chat content as NBT, trying as string" }
      content_string = packet.read_var_string rescue "System message"
      message = Chat.new(content_string)
    end

    # Read Overlay (Boolean)
    overlay = packet.read_bool

    self.new(message, overlay)
  end

  private def self.nbt_to_chat(nbt : Minecraft::NBT::Tag) : Chat
    case nbt
    when Minecraft::NBT::CompoundTag
      nbt_compound_to_chat(nbt)
    when Minecraft::NBT::StringTag
      Chat.new(nbt.value)
    else
      Chat.new(nbt.to_s)
    end
  rescue
    # Fallback for any NBT parsing errors
    Chat.new("System message (parsing error)")
  end

  private def self.nbt_compound_to_chat(nbt : Minecraft::NBT::CompoundTag) : Chat
    chat = Chat.new("")

    nbt.value.each do |key, value|
      apply_nbt_property(chat, key, value)
    end

    chat
  end

  private def self.apply_nbt_property(chat : Chat, key : String, value : Minecraft::NBT::Tag)
    case key
    when "text"
      chat.text = value.as_s if value.responds_to?(:as_s)
    when "translate"
      chat.translate = value.as_s if value.responds_to?(:as_s)
    when "color"
      chat.color = value.as_s if value.responds_to?(:as_s)
    when "bold", "italic", "underlined", "strikethrough", "obfuscated"
      apply_boolean_property(chat, key, value)
    when "extra"
      chat.extra = parse_extra_components(value) if value.is_a?(Minecraft::NBT::ListTag)
    end
  end

  private def self.apply_boolean_property(chat : Chat, key : String, value : Minecraft::NBT::Tag)
    return unless value.responds_to?(:as_i)

    boolean_value = value.as_i == 1
    case key
    when "bold"
      chat.bold = boolean_value
    when "italic"
      chat.italic = boolean_value
    when "underlined"
      chat.underlined = boolean_value
    when "strikethrough"
      chat.strikethrough = boolean_value
    when "obfuscated"
      chat.obfuscated = boolean_value
    end
  end

  private def self.parse_extra_components(list_tag : Minecraft::NBT::ListTag) : Array(Chat)
    extra_components = [] of Chat
    list_tag.value.each do |extra_nbt|
      extra_components << nbt_to_chat(extra_nbt)
    end
    extra_components
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ uses NBT text component format
      buffer.write message.to_json
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
