class Rosegold::Clientbound::KeepAlive < Rosegold::Clientbound::Packet
  property \
    keep_alive_id : Int64

  def initialize(@keep_alive_id : Int64)
  end

  def self.read(packet)
    self.new(
      packet.read_long
    )
  end

  def callback(client)
    Log.debug { "rx <- KeepAlive: #{@keep_alive_id}" }
    client.queue_packet Serverbound::KeepAlive.new keep_alive_id
  end
end
