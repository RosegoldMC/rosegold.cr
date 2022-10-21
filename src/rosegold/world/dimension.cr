require "./chunk"

class Rosegold::World::Dimension
  alias ChunkPos = {Int32, Int32}

  @chunks = Hash(ChunkPos, Chunk).new

  getter min_y
  getter world_height

  def initialize(@min_y = -64, @world_height = 256 + 64 + 64); end

  def load_chunk(chunk_pos : ChunkPos, chunk : Chunk)
    @chunks[chunk_pos] = chunk
  end

  def unload_chunk(chunk_pos : ChunkPos)
    @chunks.delete chunk_pos
  end

  def block_state(location : Vec3d) : UInt16 | Nil
    block_state location.floored_i32
  end

  def block_state(location : Vec3i) : UInt16 | Nil
    x, y, z = location
    block_state x, y, z
  end

  def block_state(x : Int32, y : Int32, z : Int32) : UInt16 | Nil
    chunk_pos = {x >> 4, z >> 4}
    @chunks[chunk_pos]?.try &.block_state(x, y, z)
  end

  def set_block_state(x : Int32, y : Int32, z : Int32, block_state : UInt16)
    chunk_pos = {x >> 4, z >> 4}
    @chunks[chunk_pos]?.try &.set_block_state(x, y, z, block_state)
  end
end
