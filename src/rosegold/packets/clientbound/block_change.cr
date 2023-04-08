require "../packet"

class Rosegold::Clientbound::BlockChange < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x0c_u8

  property \
    location : Vec3i,
    block_state : UInt16

  def initialize(@location, @block_state); end

  def self.read(packet)
    self.new(
      packet.read_bit_location,
      packet.read_var_int.to_u16
    )
  end

  def callback(client)
    Log.debug { "block change #{self}" }
    client.dimension.set_block_state location, block_state
  end
end
