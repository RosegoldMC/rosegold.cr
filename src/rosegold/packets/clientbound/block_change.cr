require "../packet"

class Rosegold::Clientbound::BlockChange < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x0c_u8

  property \
    x : Int32,
    y : Int32,
    z : Int32,
    block_state : UInt16

  def initialize(@x, @y, @z, @block_state); end

  def self.read(packet)
    self.new(
      *packet.read_bit_position,
      packet.read_var_int.to_u16
    )
  end

  def callback(client)
    client.dimension.set_block_state x, y, z, block_state
  end
end
