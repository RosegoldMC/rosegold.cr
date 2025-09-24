require "../../models/chat"
require "../packet"

class Rosegold::Clientbound::PlayerChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x3A_u8, # MC 1.21.8 - Player Chat Message
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
    unsigned_content : Rosegold::Chat?,
    filter_type : UInt32,
    filter_mask : Bytes?,
    chat_type : UInt32,
    network_name : Rosegold::Chat,
    network_target_name : Rosegold::Chat?

  def initialize(@global_index, @sender, @index, @signature, @message, @timestamp, @salt, @previous_messages, @unsigned_content, @filter_type, @filter_mask, @chat_type, @network_name, @network_target_name); end

  def self.read(packet)
    # Read header
    global_index = packet.read_var_int.to_u32
    sender = packet.read_uuid
    index = packet.read_var_int.to_u32

    # Read signature (optional)
    signature = nil
    if packet.read_bool
      signature = Bytes.new(256)
      packet.read_fully(signature)
    end

    # Read body
    message = packet.read_var_string
    timestamp = packet.read_long
    salt = packet.read_long

    # Read previous messages array
    previous_count = packet.read_var_int
    previous_messages = Array(Bytes).new(previous_count)
    previous_count.times do
      message_id = packet.read_var_int # Message ID (not used)
      msg_signature = if packet.read_bool
                        sig = Bytes.new(256)
                        packet.read_fully(sig)
                        sig
                      else
                        Bytes.empty
                      end
      previous_messages << msg_signature unless msg_signature.empty?
    end

    # Read unsigned content (optional)
    unsigned_content = nil
    if packet.read_bool
      unsigned_content = Rosegold::Chat.from_json(packet.read_var_string)
    end

    # Read filter type and mask
    filter_type = packet.read_var_int.to_u32
    filter_mask = nil
    if filter_type == 2_u32                   # PARTIALLY_FILTERED
      mask_size = (message.bytesize + 7) // 8 # ceiling division
      filter_mask = Bytes.new(mask_size)
      packet.read_fully(filter_mask)
    end

    # Read chat formatting
    chat_type = packet.read_var_int.to_u32
    network_name = Rosegold::Chat.from_json(packet.read_var_string)
    network_target_name = nil
    if packet.read_bool
      network_target_name = Rosegold::Chat.from_json(packet.read_var_string)
    end

    self.new(global_index, sender, index, signature, message, timestamp, salt, previous_messages, unsigned_content, filter_type, filter_mask, chat_type, network_name, network_target_name)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      # Write header
      buffer.write global_index
      buffer.write sender
      buffer.write index

      # Write signature
      if sig = signature
        buffer.write true
        buffer.write sig
      else
        buffer.write false
      end

      # Write body
      buffer.write message
      buffer.write_full timestamp
      buffer.write_full salt

      # Write previous messages
      buffer.write previous_messages.size.to_u32
      previous_messages.each do |msg_sig|
        buffer.write 0_u32 # Message ID placeholder
        if msg_sig.size > 0
          buffer.write true
          buffer.write msg_sig
        else
          buffer.write false
        end
      end

      # Write unsigned content
      if unsigned = unsigned_content
        buffer.write true
        buffer.write unsigned.to_json
      else
        buffer.write false
      end

      # Write filter
      buffer.write filter_type
      if mask = filter_mask
        buffer.write mask
      end

      # Write chat formatting
      buffer.write chat_type
      buffer.write network_name.to_json
      if target = network_target_name
        buffer.write true
        buffer.write target.to_json
      else
        buffer.write false
      end
    end.to_slice
  end

  def callback(client)
    Log.info { "[CHAT] #{network_name}: #{message}" }

    # Update chat manager with received message info
    if sig = signature
      client.chat_manager.add_last_seen_signature(sig)
    end
    client.chat_manager.increment_message_count
  end
end
