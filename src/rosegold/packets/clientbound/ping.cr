require "../packet"

class Rosegold::Clientbound::Ping < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x36_u8, # MC 1.21.8,
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
