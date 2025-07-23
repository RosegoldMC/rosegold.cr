require "../../models/chat"
require "../packet"

class Rosegold::Clientbound::ChatMessage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x0F_u8, # MC 1.18
    767_u32 => 0x06_u8, # MC 1.21
    769_u32 => 0x06_u8, # MC 1.21.4,
    771_u32 => 0x06_u8, # MC 1.21.6,
    772_u32 => 0x3A_u8, # MC 1.21.8,
  })

  property \
    message : Rosegold::Chat,
    position : UInt8,
    sender : UUID

  def initialize(@message, @position = 0, @sender = UUID.empty); end

  def self.read(packet)
    self.new(
      Rosegold::Chat.from_json(packet.read_var_string),
      packet.read_byte,
      packet.read_uuid
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write message.to_json
      buffer.write position
      buffer.write sender
    end.to_slice
  end

  def callback(client)
    Log.info { "[CHAT] " + message.to_s }
  end
end
