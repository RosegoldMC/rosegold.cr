require "../packet"

class Rosegold::Clientbound::KeepAlive < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x21_u8

  property keep_alive_id : Int64

  def initialize(@keep_alive_id); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def callback(client)
    client.queue_packet Serverbound::KeepAlive.new keep_alive_id
  end
end
