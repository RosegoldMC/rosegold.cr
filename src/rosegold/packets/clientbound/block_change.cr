require "../packet"

class Rosegold::Clientbound::BlockChange < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x0c_u8, # MC 1.18
    767_u32 => 0x09_u8, # MC 1.21
    771_u32 => 0x09_u8, # MC 1.21.6
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
