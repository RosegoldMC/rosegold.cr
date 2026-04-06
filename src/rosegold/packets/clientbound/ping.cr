require "../packet"

class Rosegold::Clientbound::Ping < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x36_u32, # MC 1.21.8
    774_u32 => 0x3B_u32, # MC 1.21.11
    775_u32 => 0x3D_u32, # MC 26.1
  })

  property ping_id : Int32

  def initialize(@ping_id); end

  def self.read(packet)
    self.new(packet.read_int)
  end

  def callback(client)
    client.queue_packet Serverbound::Pong.new ping_id
  end
end
