require "../../models/chat"

class Rosegold::Clientbound::Chat < Rosegold::Clientbound::Packet
  Log = ::Log.for(self)

  property \
    message : Rosegold::Chat,
    position : UInt8,
    sender : UUID

  def initialize(@message, @position, @sender)
  end

  def self.read(packet)
    self.new(
      Rosegold::Chat.from_json(packet.read_var_string),
      packet.read_byte || 0_u8,
      packet.read_uuid
    )
  end

  def callback(client)
    Log.info { message }
  end
end
