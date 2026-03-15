require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::PlayerChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x3A_u32, # MC 1.21.8
    774_u32 => 0x3F_u32, # MC 1.21.11
  })

  property \
    global_index : UInt32,
    sender : UUID,
    index : UInt32,
    signature : Bytes?,
    message : String,
    timestamp : Int64,
    salt : Int64,
    previous_messages : Array(Bytes),
    unsigned_content : Rosegold::TextComponent?,
    filter_type : UInt32,
    filter_mask : Bytes?,
    chat_type : UInt32,
    network_name : Rosegold::TextComponent,
    network_target_name : Rosegold::TextComponent?

  def initialize(@global_index, @sender, @index, @signature, @message, @timestamp, @salt, @previous_messages, @unsigned_content, @filter_type, @filter_mask, @chat_type, @network_name, @network_target_name); end

  def self.read(packet)
    global_index = packet.read_var_int.to_u32
    sender = packet.read_uuid
    index = packet.read_var_int.to_u32

    signature = nil
    if packet.read_bool
      signature = Bytes.new(256)
      packet.read_fully(signature)
    end

    message = packet.read_var_string
    timestamp = packet.read_long
    salt = packet.read_long

    # Previous messages: packed MessageSignature format
    previous_count = packet.read_var_int
    previous_messages = Array(Bytes).new(previous_count)
    previous_count.times do
      packed_id = packet.read_var_int - 1
      if packed_id == -1
        # Full signature follows
        sig = Bytes.new(256)
        packet.read_fully(sig)
        previous_messages << sig
      end
      # else: cached signature reference, nothing to read
    end

    # Unsigned content (optional, NBT text component)
    unsigned_content = packet.read_bool ? packet.read_text_component : nil

    # Filter type and mask
    filter_type = packet.read_var_int.to_u32
    filter_mask = nil
    if filter_type == 2_u32 # PARTIALLY_FILTERED
      long_count = packet.read_var_int
      filter_mask = Bytes.new(long_count * 8)
      packet.read_fully(filter_mask)
    end

    # Chat formatting (ChatType.Bound)
    chat_type = packet.read_var_int.to_u32
    network_name = packet.read_text_component
    network_target_name = packet.read_bool ? packet.read_text_component : nil

    self.new(global_index, sender, index, signature, message, timestamp, salt, previous_messages, unsigned_content, filter_type, filter_mask, chat_type, network_name, network_target_name)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      buffer.write global_index
      buffer.write sender
      buffer.write index

      if sig = signature
        buffer.write true
        buffer.write sig
      else
        buffer.write false
      end

      buffer.write message
      buffer.write_full timestamp
      buffer.write_full salt

      # Previous messages (packed format)
      buffer.write previous_messages.size.to_u32
      previous_messages.each do |msg_sig|
        # id + 1 == 0 means full signature follows
        buffer.write 0_u32
        buffer.write msg_sig
      end

      if unsigned = unsigned_content
        buffer.write true
        unsigned.write(buffer)
      else
        buffer.write false
      end

      buffer.write filter_type
      if mask = filter_mask
        buffer.write (mask.size // 8).to_u32
        buffer.write mask
      end

      buffer.write chat_type
      network_name.write(buffer)
      if target = network_target_name
        buffer.write true
        target.write(buffer)
      else
        buffer.write false
      end
    end.to_slice
  end

  def callback(client)
    Log.info { "[CHAT] #{network_name}: #{message}" }

    if sig = signature
      client.chat_manager.add_last_seen_signature(sig)
    end
    client.chat_manager.increment_message_count
  end
end
