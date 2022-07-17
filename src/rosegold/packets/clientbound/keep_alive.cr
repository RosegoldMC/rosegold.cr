class Rosegold::Clientbound::KeepAlive < Rosegold::Clientbound::Packet
  property \
    keep_alive_id : UInt64

  def initialize(@keep_alive_id : UInt64)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int
    )
  end

  def callback(client)
    client.queue_packet Serverbound::KeepAlive.new keep_alive_id
  end
end
