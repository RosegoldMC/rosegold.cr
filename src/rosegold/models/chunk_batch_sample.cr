struct Rosegold::ChunkBatchSample
  property millis_per_chunk : Float64
  property batch_size : Int32
  property timestamp : Time

  def initialize(@millis_per_chunk : Float64, @batch_size : Int32, @timestamp : Time = Time.utc)
  end
end