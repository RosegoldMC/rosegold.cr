require "../../models/chat"

class Rosegold::Clientbound::OpenWindow < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x34_u8, # MC 1.21.8,
  })

  property \
    window_id : UInt32,
    window_type : UInt32,
    window_title : Rosegold::Chat # NBT text component

  def initialize(@window_id, @window_type, @window_title)
  end

  def self.read(packet)
    window_id = packet.read_var_int
    window_type = packet.read_var_int

    # Read window title as NBT text component (MC 1.21.8+)
    begin
      content_nbt = packet.read_nbt_unamed
      window_title = nbt_to_chat(content_nbt)
    rescue
      # Fallback if NBT reading fails
      Log.warn { "Failed to parse window title as NBT, using default" }
      window_title = Rosegold::Chat.new("Window")
    end

    self.new(window_id, window_type, window_title)
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
    Chat.new("Window")
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
      buffer.write window_id
      buffer.write window_type
      # Write as NBT text component
      buffer.write window_title.to_json
    end.to_slice
  end

  def callback(client)
    # Clamp window_id to valid UInt8 range
    clamped_id = window_id > 255 ? 255_u8 : window_id.to_u8
    client.window = Window.new \
      client, clamped_id, window_title, window_type
    Log.debug { "Server opened window id=#{window_id} type=#{window_type} title: #{window_title}" }
  end
end
