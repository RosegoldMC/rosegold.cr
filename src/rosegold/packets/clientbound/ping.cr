class Rosegold::Clientbound::Ping < Rosegold::Clientbound::Packet
  property \
    ping_id : Int32

  def initialize(@ping_id)
  end

  def self.read(packet)
    self.new(
      packet.read_int32
    )
  end

  def callback(client)
    client.queue_packet Serverbound::Pong.new ping_id
  end
end
