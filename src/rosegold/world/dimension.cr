require "nbt"
require "./chunk"

class Rosegold::Dimension
  alias ChunkPos = {Int32, Int32}

  getter chunks = Hash(ChunkPos, Chunk).new

  getter name : String
  getter nbt : NBT::Tag
  getter min_y = -64
  getter world_height = 256 + 64 + 64

  def initialize(@name, @nbt)
    @min_y = @nbt["min_y"].as_i
    @world_height = @nbt["height"].as_i
  end

  def self.new
    self.new "minecraft:overworld", NBT::Tag.new({
      "min_y"  => NBT::Tag.new(-64_i32),
      "height" => NBT::Tag.new(384_i32),
    })
  end

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
