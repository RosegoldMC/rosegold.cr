require "../packet"
require "../../models/text_component"

class Rosegold::Clientbound::Disconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x1c_u8, # MC 1.21.8,
  })

  property reason : TextComponent

  def initialize(@reason); end

  def initialize(reason_string : String)
    @reason = TextComponent.new(reason_string)
  end

  def self.read(packet)
    # MC 1.21+ uses NBT text component format

    reason_nbt = packet.read_nbt_unamed
    text_component = nbt_to_text_component(reason_nbt)
    self.new text_component
  rescue
    # Fallback if NBT reading fails
    Log.warn { "Failed to parse disconnect reason as NBT, trying as string" }
    reason_string = packet.read_var_string rescue "Unknown disconnect reason"
    self.new TextComponent.new(reason_string)
  end

  private def self.nbt_to_text_component(nbt : Minecraft::NBT::Tag) : TextComponent
    text_component = TextComponent.new("")

    case nbt
    when Minecraft::NBT::CompoundTag
      # Handle compound NBT with text component fields
      nbt.value.each do |key, value|
        case key
        when "text"
          text_component.text = value.as_s if value.responds_to?(:as_s)
        when "translate"
          text_component.translate = value.as_s if value.responds_to?(:as_s)
        when "color"
          text_component.color = value.as_s if value.responds_to?(:as_s)
        when "bold"
          text_component.bold = value.as_i == 1 if value.responds_to?(:as_i)
        when "italic"
          text_component.italic = value.as_i == 1 if value.responds_to?(:as_i)
        when "underlined"
          text_component.underlined = value.as_i == 1 if value.responds_to?(:as_i)
        when "strikethrough"
          text_component.strikethrough = value.as_i == 1 if value.responds_to?(:as_i)
        when "obfuscated"
          text_component.obfuscated = value.as_i == 1 if value.responds_to?(:as_i)
        end
      end
    when Minecraft::NBT::StringTag
      # Simple string NBT
      text_component.text = nbt.value
    else
      # Fallback for other NBT types
      text_component.text = nbt.to_s
    end

    text_component
  rescue
    # Fallback for any NBT parsing errors
    TextComponent.new("Disconnect reason (parsing error)")
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ uses NBT text component format
      reason.write(buffer)
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason.to_s
  end
end
