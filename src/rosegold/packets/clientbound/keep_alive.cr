class Rosegold::Clientbound::KeepAlive < Rosegold::Clientbound::Packet
  property \
    keep_alive_id : UInt64

  def initialize(@keep_alive_id : UInt64)
  end

  def self.read(packet)
    self.new(
      packet.read_uint64
    )
  end

  def callback(client)
    client.send_packet Serverbound::KeepAlive.new keep_alive_id
  end
end
