require "./chunk"

class Rosegold::World::Dimension
  alias ChunkPos = {Int32, Int32}

  @chunks = Hash(ChunkPos, Chunk).new

  def set_chunk(chunk_pos : ChunkPos, chunk : Chunk)
    @chunks[chunk_pos] = chunk
  end

  def block_state(x : Int32, y : Int32, z : Int32) : UInt16 | Nil
    chunk_pos = {x >> 4, z >> 4}
    @chunks[chunk_pos]?.try &.block_state(x, y, z)
  end
end
