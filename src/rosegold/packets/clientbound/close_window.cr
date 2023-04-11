require "../packet"

class Rosegold::Clientbound::CloseWindow < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x12_u8

  property \
    window_id : UInt32

  def initialize(@window_id)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int,
    )
  end

  def callback(client)
    if client.window.id == 0
      Log.warn { "Server closed the inventory window" }
      return
    end
    client.window.close
    client.window = client.inventory
  end
end
