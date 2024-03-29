require "../packet"

class Rosegold::Clientbound::SetCompression < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x03_u8
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
