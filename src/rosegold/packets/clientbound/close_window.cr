require "../packet"

class Rosegold::Clientbound::CloseWindow < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x13_u8

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
    if window_id == client.window.id
      Log.debug { "Server closed window #{client.window}" }
      client.window.handle_closed
      client.window = client.inventory
    else
      Log.warn { "Server closed the wrong window: #{window_id}. Ignoring." }
      Log.debug { self }
    end
  end
end
