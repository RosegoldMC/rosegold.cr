require "../packet"

class Rosegold::Clientbound::Disconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x1c_u8, # MC 1.21.8,
  })

  property reason : Chat

  def initialize(@reason); end

  def self.read(packet)
    if Client.protocol_version >= 767_u32
      # MC 1.21+ uses NBT text component format
      begin
        reason_nbt = packet.read_nbt_unamed
        chat = nbt_to_chat(reason_nbt)
        self.new chat
      rescue
        # Fallback if NBT reading fails
        Log.warn { "Failed to parse disconnect reason as NBT, trying as string" }
        reason_string = packet.read_var_string rescue "Unknown disconnect reason"
        self.new Chat.new(reason_string)
      end
    else
      # Older versions use JSON chat format
      reason_json = packet.read_var_string
      begin
        self.new Chat.from_json(reason_json)
      rescue JSON::ParseException
        Log.warn { "Failed to parse disconnect reason as JSON: #{reason_json.inspect}" }
        self.new Chat.new(reason_json)
      end
    end
  end

  private def self.nbt_to_chat(nbt : Minecraft::NBT::Tag) : Chat
    chat = Chat.new("")

    case nbt
    when Minecraft::NBT::CompoundTag
      # Handle compound NBT with text component fields
      nbt.value.each do |key, value|
        case key
        when "text"
          chat.text = value.as_s if value.responds_to?(:as_s)
        when "translate"
          chat.translate = value.as_s if value.responds_to?(:as_s)
        when "color"
          chat.color = value.as_s if value.responds_to?(:as_s)
        when "bold"
          chat.bold = value.as_i == 1 if value.responds_to?(:as_i)
        when "italic"
          chat.italic = value.as_i == 1 if value.responds_to?(:as_i)
        when "underlined"
          chat.underlined = value.as_i == 1 if value.responds_to?(:as_i)
        when "strikethrough"
          chat.strikethrough = value.as_i == 1 if value.responds_to?(:as_i)
        when "obfuscated"
          chat.obfuscated = value.as_i == 1 if value.responds_to?(:as_i)
        end
      end
    when Minecraft::NBT::StringTag
      # Simple string NBT
      chat.text = nbt.value
    else
      # Fallback for other NBT types
      chat.text = nbt.to_s
    end

    chat
  rescue
    # Fallback for any NBT parsing errors
    Chat.new("Disconnect reason (parsing error)")
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      if Client.protocol_version >= 767_u32
        # MC 1.21+ uses text component format
        buffer.write reason.to_json
      else
        # Older versions use chat format
        buffer.write reason.to_json
      end
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason
  end
end
