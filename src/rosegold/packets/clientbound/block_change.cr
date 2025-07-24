require "../packet"

class Rosegold::Clientbound::BlockChange < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x08_u8, # MC 1.21.8,
  })

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
    client.dimension.set_block_state location, block_state
  end
end
