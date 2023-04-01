require "../../models/chat"

class Rosegold::Clientbound::OpenWindow < Rosegold::Clientbound::Packet
  Log = ::Log.for(self)

  class_getter packet_id = 0x2E_u8

  property \
    window_id : UInt32,
    window_type : UInt32,
    window_title : Rosegold::Chat

  def initialize(@window_id, @window_type, @window_title)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int,
      packet.read_var_int,
      Rosegold::Chat.from_json(packet.read_var_string),
    )
  end

  def callback(client)
    client.current_window = Window.new self
  end
end
