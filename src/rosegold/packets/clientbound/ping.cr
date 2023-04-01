require "../packet"

class Rosegold::Clientbound::Ping < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x30_u8

  property ping_id : Int32

  def initialize(@ping_id); end

  def self.read(packet)
    self.new(packet.read_int)
  end

  def callback(client)
    client.queue_packet Serverbound::Pong.new ping_id
  end
end
