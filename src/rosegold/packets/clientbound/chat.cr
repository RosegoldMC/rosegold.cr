require "../../models/chat"
require "../packet"

class Rosegold::Clientbound::Chat < Rosegold::Clientbound::Packet
  Log = ::Log.for(self)

  class_getter packet_id = 0x0f_u8

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
      buffer.write @@packet_id
      buffer.write message.to_json
      buffer.write position
      buffer.write sender
    end.to_slice
  end

  def callback(client)
    Log.info { "[CHAT] " + message.to_s }
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Clientbound::Chat
