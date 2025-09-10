require "./chunk"
require "./entity"

class Rosegold::Dimension
  alias ChunkPos = {Int32, Int32}

  getter chunks = Hash(ChunkPos, Rosegold::Chunk).new

  getter name : String
  getter nbt : Minecraft::NBT::Tag
  getter min_y = -64
  getter world_height = 256 + 64 + 64

  property entities : Hash(UInt64, Entity) = Hash(UInt64, Entity).new

  def initialize(@name, @nbt)
    @min_y = @nbt["min_y"].as_i32
    @world_height = @nbt["height"].as_i32
  end

  def self.new
    self.new "minecraft:overworld", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(-64_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(384_i32).as(Minecraft::NBT::Tag),
    })
  end

  def self.new_nether
    self.new "minecraft:the_nether", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(0_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(128_i32).as(Minecraft::NBT::Tag),
    })
  end

  def self.new_end
    self.new "minecraft:the_end", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(0_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(256_i32).as(Minecraft::NBT::Tag),
    })
  end

  # TODO: set dimension based on dimension_type via registry
  def self.for_dimension_name(name : String)
    case name
    when "minecraft:the_nether"
      new_nether
    when "minecraft:the_end"
      new_end
    else
      new # defaults to overworld
    end
  end

  def load_chunk(chunk : Chunk)
    chunk_pos = {chunk.x, chunk.z}
    @chunks[chunk_pos] = chunk
  end

  def unload_chunk(chunk_pos : ChunkPos)
    @chunks.delete chunk_pos
  end

  def block_state(location : Vec3d) : UInt16 | Nil
    block_state location.block
  end

  def block_state(location : Vec3i) : UInt16 | Nil
    x, y, z = location
    block_state x, y, z
  end

  def block_state(x : Int32, y : Int32, z : Int32) : UInt16 | Nil
    chunk_pos = {x >> 4, z >> 4}
    @chunks[chunk_pos]?.try &.block_state(x, y, z)
  end

  def set_block_state(location : Vec3i, block_state : UInt16)
    set_block_state location.x, location.y, location.z, block_state
  end

  def set_block_state(x : Int32, y : Int32, z : Int32, block_state : UInt16)
    chunk_pos = {x >> 4, z >> 4}
    @chunks[chunk_pos]?.try &.set_block_state(x, y, z, block_state)
  end

  def raycast_entity(start : Vec3d, look : Vec3d, max_distance : Float64) : Entity?
    closest_entity = nil
    closest_distance = Float64::INFINITY

    ray_end = start + look * max_distance

    entities.each_value do |entity|
      next unless entity.living?

      bounding_box = entity.bounding_box
      distance = bounding_box.ray_intersection(start, ray_end)
      next if distance.nil?

      if distance < closest_distance
        closest_entity = entity
        closest_distance = distance
      end
    end

    closest_entity
  end
end
