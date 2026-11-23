require "./chunk"
require "./entity"
require "./mining_prediction"

class Rosegold::Dimension
  alias ChunkPos = {Int32, Int32}

  REGISTRY_ID = "minecraft:dimension_type"

  getter chunks = Hash(ChunkPos, Rosegold::Chunk).new

  getter name : String
  getter nbt : Minecraft::NBT::Tag
  getter min_y = -64
  getter world_height = 256 + 64 + 64

  property dimension_type : UInt32 = 0_u32
  property entities : Hash(UInt64, Entity) = Hash(UInt64, Entity).new
  property time_of_day : Int64 = 6000_i64
  property world_age : Int64 = 0_i64

  @interaction_predictions = MiningPrediction.new

  def initialize(@name, @nbt)
    if (compound = @nbt).is_a?(Minecraft::NBT::CompoundTag)
      @min_y = compound["min_y"]?.try(&.as_i32) || @min_y
      @world_height = compound["height"]?.try(&.as_i32) || @world_height
    end
  end

  def self.new
    self.new "minecraft:overworld", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(-64_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(384_i32).as(Minecraft::NBT::Tag),
    })
  end

  def self.new_nether
    # Vanilla `the_nether` dimension type: height=256 (16 sections), logical_height=128.
    # The wire format always uses the full height, even though the build limit is 128.
    self.new "minecraft:the_nether", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(0_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(256_i32).as(Minecraft::NBT::Tag),
    })
  end

  def self.new_end
    self.new "minecraft:the_end", Minecraft::NBT::CompoundTag.new({
      "min_y"  => Minecraft::NBT::IntTag.new(0_i32).as(Minecraft::NBT::Tag),
      "height" => Minecraft::NBT::IntTag.new(256_i32).as(Minecraft::NBT::Tag),
    })
  end

  # Build a Dimension from the server-provided dimension_type registry entry.
  # `dimension_type` indexes into `minecraft:dimension_type`, whose codec NBT
  # carries the authoritative `min_y` / `height` for this server. Falls back
  # to vanilla defaults keyed by dimension name when the registry is missing
  # or the entry is unparseable.
  def self.from_registry(name : String, dimension_type : UInt32, registries : Hash(String, Rosegold::Clientbound::RegistryData))
    nbt = registry_dimension_nbt(dimension_type, registries)
    dim = nbt ? new(name, nbt) : for_dimension_name(name)
    dim.dimension_type = dimension_type
    dim
  end

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

  private def self.registry_dimension_nbt(dimension_type : UInt32, registries : Hash(String, Rosegold::Clientbound::RegistryData)) : Minecraft::NBT::CompoundTag?
    registry = registries[REGISTRY_ID]?
    return unless registry

    entry = registry.entries[dimension_type.to_i32]?
    return unless entry

    data = entry[:data]
    return unless data

    tag = Minecraft::NBT::Tag.read(Minecraft::IO::Memory.new(data))
    tag.is_a?(Minecraft::NBT::CompoundTag) ? tag : nil
  rescue ex
    Log.warn { "Failed to parse dimension_type registry entry #{dimension_type}: #{ex}" }
    nil
  end

  def load_chunk(chunk : Chunk)
    chunk_pos = {chunk.x, chunk.z}
    @interaction_predictions.clear_chunk chunk_pos
    @chunks[chunk_pos] = chunk
  end

  def chunk_at?(x : Int32, z : Int32) : Chunk?
    chunk_pos = {x, z}
    @chunks[chunk_pos]?
  end

  def unload_chunk(chunk_pos : ChunkPos)
    @interaction_predictions.clear_chunk chunk_pos
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

  # Predicts the fluid block state (or air) left by breaking a loaded non-air block.
  def predict_block_break(location : Vec3i, sequence : Int32) : Bool
    current = interaction_block_state(location) || return false
    mc = MCData.default
    return false if mc.air_states.includes?(current)
    predict_interaction_block_state location, MiningPrediction.replacement_state(current, mc), sequence
  end

  # Returns the pending interaction state or the authoritative block state.
  def interaction_block_state(location : Vec3i) : UInt16?
    interaction_block_state location.x, location.y, location.z
  end

  def interaction_block_state(x : Int32, y : Int32, z : Int32) : UInt16?
    @interaction_predictions[x, y, z] || block_state(x, y, z)
  end

  # Records a verified interaction result separately from chunk data. Returns
  # false for unknown states, unloaded or out-of-bounds positions, or a sequence
  # older than the prediction already pending at this position.
  def predict_interaction_block_state(location : Vec3i, state : UInt16, sequence : Int32) : Bool
    y_offset = location.y.to_i64 - min_y
    return false unless 0 <= y_offset < world_height && block_state(location)
    state_name = MCData.default.block_state_names[state]? || return false
    return false if state_name.empty?
    @interaction_predictions.predict location.x, location.y, location.z, sequence, state
  end

  # Ends predictions up to and including `sequence`, revealing the latest
  # authoritative block state wherever a prediction ends.
  def acknowledge_interaction_predictions(sequence : Int32) : Nil
    @interaction_predictions.acknowledge sequence
  end

  def clear_interaction_predictions : Nil
    @interaction_predictions.clear
  end

  def mining_block_state(x : Int32, y : Int32, z : Int32) : UInt16?
    interaction_block_state x, y, z
  end

  def acknowledge_mining_predictions(sequence : Int32) : Nil
    acknowledge_interaction_predictions sequence
  end

  def clear_mining_predictions : Nil
    clear_interaction_predictions
  end

  # Vanilla Entity#updateFluidOnEyes: the water at the eye block, raised to a
  # full block when water is also above it, must reach above the eye. Uses
  # authoritative geometry.
  def eye_in_water?(eyes : Vec3d) : Bool
    x, y, z = eyes.block.x, eyes.block.y, eyes.block.z
    mc = MCData.default
    state = block_state(x, y, z) || return false
    own_height = MiningPrediction.water_own_height(state, mc) || return false
    above = block_state(x, y + 1, z)
    height = above && MiningPrediction.water_own_height(above, mc) ? 1.0 : own_height
    y + height > eyes.y
  end

  def raycast_entity(start : Vec3d, look : Vec3d, max_distance : Float64, passenger_id : UInt32? = nil) : Entity?
    closest_entity = nil
    closest_distance = Float64::INFINITY

    ray_end = start + look * max_distance

    entities.each_value do |entity|
      next unless entity.pickable?

      bounding_box = entity.bounding_box
      if passenger_id && entity.passenger_ids.includes?(passenger_id)
        return entity if bounding_box.contains?(start)
        next
      end
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
