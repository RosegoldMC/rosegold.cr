require "../packet"

class Rosegold::Clientbound::SetCompression < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x03_u8, # MC 1.21.8,
  })
  class_getter state = Rosegold::ProtocolState::LOGIN

  property \
    threshold : UInt32

  def initialize(@threshold)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int,
    )
  end

  def callback(client)
    client.connection.compression_threshold = threshold
  end
end
