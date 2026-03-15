# Since 1.19, this packet is just a single VarInt sequence ID.
class Rosegold::Clientbound::AcknowledgeBlockChange < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x04_u32, # MC 1.21.8
    774_u32 => 0x04_u32, # MC 1.21.11
  })

  property sequence : Int32

  def initialize(@sequence)
  end

  def self.read(packet)
    sequence = packet.read_var_int.to_i32
    self.new(sequence)
  end

  def callback(client)
    Log.debug { "dig ack sequence=#{sequence}" }
    client.pending_block_operations.delete(sequence) if sequence > 0
  end
end
