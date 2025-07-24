require "../packet"

class Rosegold::Clientbound::ChunkBatchStart < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x0C_u8, # MC 1.21.8,
  })

  def initialize; end

  def self.read(io)
    # No fields to read
    self.new
  end

  def callback(client)
    # Mark the start time of the chunk batch
    client.chunk_batch_start_time = Time.utc
  end
end
