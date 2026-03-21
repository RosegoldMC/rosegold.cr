require "../packet"

class Rosegold::Clientbound::ChunkBatchStart < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x0C_u32, # MC 1.21.8
    774_u32 => 0x0C_u32, # MC 1.21.11
  })

  def initialize; end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end

  def self.read(io)
    # No fields to read
    self.new
  end

  def callback(client)
    # Mark the start time of the chunk batch
    client.chunk_batch_start_time = Time.utc
  end
end
