require "../packet"

class Rosegold::Clientbound::ChunkBatchFinished < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    767_u32 => 0x0C_u8, # MC 1.21
    771_u32 => 0x0C_u8, # MC 1.21.6
  })

  property batch_size : Int32

  def initialize(@batch_size : Int32); end

  def self.read(io)
    batch_size = io.read_var_int.to_i32
    self.new(batch_size)
  end

  def callback(client)
    # Calculate elapsed time since batch start
    start_time = client.chunk_batch_start_time
    return unless start_time
    
    end_time = Time.utc
    duration_ms = (end_time - start_time).total_milliseconds
    
    # Calculate milliseconds per chunk
    millis_per_chunk = batch_size > 0 ? duration_ms / batch_size : 0.0
    
    # Add this sample to the client's batch timing history
    client.add_chunk_batch_sample(millis_per_chunk, batch_size)
    
    # Calculate desired chunks per tick (25 / millisPerChunk)
    # Use 25 instead of 50 to use only half bandwidth
    chunks_per_tick = millis_per_chunk > 0 ? 25.0 / millis_per_chunk : 25.0
    
    # Send acknowledgment to server
    client.send_packet! Rosegold::Serverbound::ChunkBatchReceived.new(chunks_per_tick.to_f32)
    
    # Reset batch start time
    client.chunk_batch_start_time = nil
  end
end