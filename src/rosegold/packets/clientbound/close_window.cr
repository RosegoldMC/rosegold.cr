require "../packet"

class Rosegold::Clientbound::CloseWindow < Rosegold::Clientbound::Packet
  Log = ::Log.for(self)

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
    client.current_window = Window.player_inventory
  end
end
