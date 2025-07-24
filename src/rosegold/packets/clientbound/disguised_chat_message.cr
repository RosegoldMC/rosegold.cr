require "../../models/chat"
require "../packet"

class Rosegold::Clientbound::DisguisedChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for Disguised Chat Message
  packet_ids({
    772_u32 => 0x1D_u8, # MC 1.21.8 - Disguised Chat Message
  })

  property \
    message : Rosegold::Chat,
    chat_type : UInt32,
    sender_name : Rosegold::Chat,
    target_name : Rosegold::Chat?

  def initialize(@message, @chat_type, @sender_name, @target_name); end

  def self.read(packet)
    # Read Text Component (NBT format)
    # Text Component starts with NBT tag type
    nbt_type = packet.read_byte

    message = if nbt_type == 8 # NBT String Tag (TAG_String)
                # Simple text component - just read the string
                text = packet.read_var_string
                Rosegold::Chat.new(text)
              else
                # Complex NBT component - for now, skip complex parsing
                # This would require full NBT parsing which is complex
                Rosegold::Chat.new("Complex text component")
              end

    # Read chat type (ID or inline definition)
    chat_type_id = packet.read_var_int.to_u32
    if chat_type_id == 0
      # Inline definition - read the complex chat type structure
      # Translation Key
      packet.read_var_string
      # Parameters array
      param_count = packet.read_var_int
      param_count.times do
        packet.read_var_int # parameter type
      end
      # Style (NBT) - for now, assume empty
      style_nbt_type = packet.read_byte
      if style_nbt_type != 0 # Not TAG_End
        # Skip complex NBT parsing for now
      end
    end

    # Read Sender Name (Text Component)
    sender_nbt_type = packet.read_byte
    sender_name = if sender_nbt_type == 8 # NBT String Tag
                    text = packet.read_var_string
                    Rosegold::Chat.new(text)
                  else
                    Rosegold::Chat.new("Server")
                  end

    # Read optional target name
    target_name = nil
    if packet.read_bool
      target_nbt_type = packet.read_byte
      target_name = if target_nbt_type == 8 # NBT String Tag
                      text = packet.read_var_string
                      Rosegold::Chat.new(text)
                    else
                      Rosegold::Chat.new("Target")
                    end
    end

    self.new(message, chat_type_id, sender_name, target_name)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write message.to_json
      buffer.write chat_type
      buffer.write sender_name.to_json
      if target = target_name
        buffer.write true
        buffer.write target.to_json
      else
        buffer.write false
      end
    end.to_slice
  end

  def callback(client)
    Log.info { "[DISGUISED CHAT] #{sender_name}: #{message}" }
  end
end
