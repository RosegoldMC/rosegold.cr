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
    clamped_id = window_id > 255 ? 255_u8 : window_id.to_u8
    container_size = case window_type
                     when  0 then 9  # GENERIC_9x1 (1 row × 9 = 9 slots)
                     when  1 then 18 # GENERIC_9x2 (2 rows × 9 = 18 slots)
                     when  2 then 27 # GENERIC_9x3 (3 rows × 9 = 27 slots)
                     when  3 then 36 # GENERIC_9x4 (4 rows × 9 = 36 slots)
                     when  4 then 45 # GENERIC_9x5 (5 rows × 9 = 45 slots)
                     when  5 then 54 # GENERIC_9x6 (6 rows × 9 = 54 slots)
                     when  6 then 9  # GENERIC_3x3 (Dispenser: 3×3 = 9 slots)
                     when  7 then 9  # CRAFTER_3x3 (3×3 = 9 slots)
                     when  8 then 3  # ANVIL (3 slots: 2 input + 1 output)
                     when  9 then 1  # BEACON (1 payment slot)
                     when 10 then 3  # BLAST_FURNACE (3 slots: input, fuel, output)
                     when 11 then 5  # BREWING_STAND (5 slots: 3 bottles + 1 ingredient + 1 fuel)
                     when 12 then 10 # CRAFTING (9 crafting + 1 result = 10 slots)
                     when 13 then 2  # ENCHANTMENT (2 slots: item + lapis)
                     when 14 then 3  # FURNACE (3 slots: input, fuel, output)
                     else         27 # Default to chest size
                     end

    ContainerMenu.open(client, clamped_id, window_title, window_type, container_size)
    Log.debug { "Server opened window id=#{window_id} type=#{window_type} size=#{container_size} title: #{window_title}" }
  end
end
