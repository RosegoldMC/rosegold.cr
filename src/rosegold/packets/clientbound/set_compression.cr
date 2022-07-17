class Rosegold::Clientbound::SetCompression < Rosegold::Clientbound::Packet
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
    client.compression_threshold = threshold
  end
end
