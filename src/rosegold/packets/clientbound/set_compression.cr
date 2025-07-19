require "../packet"

class Rosegold::Clientbound::SetCompression < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x03_u8, # MC 1.18
    767_u32 => 0x03_u8, # MC 1.21
    771_u32 => 0x03_u8, # MC 1.21.6
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