class Rosegold::Bot
  record BlockSnapshot, position : Vec3i, state_id : UInt16, name : String, properties : Hash(String, String)
  record EntitySnapshot, id : UInt32, uuid : UUID, type : String?, position : Vec3d,
    velocity : Vec3d, yaw : Float32, pitch : Float32, on_ground : Bool
  private alias BlockSearchKey = Tuple(Float64, Int32, Int32, Int32)
  private alias BlockSearchMatch = Tuple(BlockSearchKey, BlockSnapshot)

  # The current dimension, including its live chunks and entities.
  def world : Dimension
    client.dimension
  end

  # Returns received block state, or nil outside loaded chunks and world height.
  # Properties use the versioned game data's string values.
  def block_at(position : Vec3i) : BlockSnapshot?
    state = world.block_state(position)
    return unless state
    description = MCData.default.block_state_names[state]?
    return unless description
    return if description.empty?
    name, _, state_properties = description.partition('[')
    properties = {} of String => String
    unless state_properties.empty?
      state_properties.rchop(']').split(", ").each do |property|
        key, _, value = property.partition('=')
        properties[key] = value
      end
    end
    BlockSnapshot.new(position, state, name, properties)
  end

  # Floors fractional coordinates, including negative coordinates, to a block.
  def block_at(position : Vec3d) : BlockSnapshot?
    block_at(position.block)
  end

  # Searches loaded blocks within a spherical radius, nearest first.
  # Distances use block coordinates. Equal distances sort by x, y, then z.
  def find_blocks(name : String, *, radius : Number, center : Vec3d | Vec3i = location, limit : Int32 = 1) : Array(BlockSnapshot)
    radius = radius.to_f64
    raise ArgumentError.new("radius must be finite and nonnegative") unless radius.finite? && radius >= 0
    raise ArgumentError.new("limit must be nonnegative") if limit < 0
    return [] of BlockSnapshot if limit == 0
    matches = [] of BlockSearchMatch
    center = center.to_f64
    raise ArgumentError.new("center must be finite") unless center.x.finite? && center.y.finite? && center.z.finite?
    name = name.lchop("minecraft:")
    state_prefix = "#{name}["
    state_names = MCData.default.block_state_names
    dimension = world
    dimension.chunks.each_value do |chunk|
      min_x = Math.max(chunk.x.to_i64 * 16, (center.x - radius).ceil)
      max_x = Math.min(chunk.x.to_i64 * 16 + 15, (center.x + radius).floor)
      min_z = Math.max(chunk.z.to_i64 * 16, (center.z - radius).ceil)
      max_z = Math.min(chunk.z.to_i64 * 16 + 15, (center.z + radius).floor)
      min_y = Math.max(dimension.min_y, (center.y - radius).ceil)
      max_y = Math.min(dimension.min_y + dimension.world_height - 1, (center.y + radius).floor)
      next if min_x > max_x || min_y > max_y || min_z > max_z
      (min_x.to_i32..max_x.to_i32).each do |block_x|
        (min_y.to_i32..max_y.to_i32).each do |block_y|
          (min_z.to_i32..max_z.to_i32).each do |block_z|
            position = Vec3i.new(block_x, block_y, block_z)
            distance = (position.to_f64 - center).length
            next if distance > radius
            state = dimension.block_state(position)
            next unless state
            state_name = state_names[state]?
            next unless state_name && (state_name == name || state_name.starts_with?(state_prefix))
            key = {distance, block_x, block_y, block_z}
            next if matches.size == limit && key >= matches.first[0]
            snapshot = block_at(position)
            next unless snapshot
            retain_block_match(matches, {key, snapshot}, limit)
          end
        end
      end
    end
    matches.sort_by!(&.first).map(&.last)
  end

  # A max-heap bounds storage and avoids sorting the retained set on every block.
  private def retain_block_match(matches : Array(BlockSearchMatch), match : BlockSearchMatch, limit : Int32)
    if matches.size < limit
      index = matches.size
      matches << match
      while index > 0
        parent = (index - 1) // 2
        break if matches[parent][0] >= match[0]
        matches[index] = matches[parent]
        index = parent
      end
    else
      index = 0
      while (child = index * 2 + 1) < matches.size
        right = child + 1
        child = right if right < matches.size && matches[right][0] > matches[child][0]
        break if matches[child][0] <= match[0]
        matches[index] = matches[child]
        index = child
      end
    end
    matches[index] = match
  end

  # Returns the nearest matching loaded block within the required radius.
  def find_block(name : String, *, radius : Number, center : Vec3d | Vec3i = location) : BlockSnapshot?
    find_blocks(name, radius: radius, center: center, limit: 1).first?
  end

  # Detached snapshots of entities currently tracked in this dimension.
  def entities : Array(EntitySnapshot)
    world.entities.values.map { |entity| snapshot_entity(entity) }
  end

  # Returns a detached entity snapshot, or nil if the entity is not tracked.
  def entity(id : Int) : EntitySnapshot?
    return if id < 0
    world.entities[id.to_u64]?.try { |entity| snapshot_entity(entity) }
  end

  # Returns the nearest tracked entity, optionally bounded by distance.
  def nearest_entity(*, max_distance : Number? = nil) : EntitySnapshot?
    nearest_entity(max_distance: max_distance) { true }
  end

  # Filters detached entity snapshots before choosing the nearest match.
  def nearest_entity(*, max_distance : Number? = nil, &predicate : EntitySnapshot -> Bool) : EntitySnapshot?
    distance_limit = max_distance.try(&.to_f64) || Float64::INFINITY
    raise ArgumentError.new("max_distance must be nonnegative") if distance_limit.nan? || distance_limit < 0
    origin = location
    entities.select { |entity| (entity.position - origin).length <= distance_limit && predicate.call(entity) }
      .min_by? { |entity| {(entity.position - origin).length, entity.id} }
  end

  # The player's server-reported experience level.
  def experience_level : UInt32
    client.player.experience_level
  end

  # The player's server-reported progress toward the next experience level.
  def experience_progress : Float32
    client.player.experience_progress
  end

  # The player's server-reported total experience.
  def total_experience : UInt32
    client.player.total_experience
  end

  # Clears a pending jump without changing other movement inputs.
  def stop_jump : Nil
    client.physics.jump_queued = false
  end

  private def snapshot_entity(entity : Entity) : EntitySnapshot
    EntitySnapshot.new(entity.entity_id, entity.uuid, entity.metadata.try(&.name), entity.position,
      entity.velocity, entity.yaw, entity.pitch, entity.on_ground?)
  end
end
