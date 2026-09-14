require "../spec_helper"

# This accessor exercises Physics' collision query without making it public API.
module Rosegold
  class Client
    def dimension_for_collision_test=(value : Dimension)
      self.dimension = value
    end
  end

  class Physics
    def no_collision_for_test?(box : AABBd) : Bool
      no_collision?(box)
    end
  end
end

private def custom_dimension : Rosegold::Dimension
  Rosegold::Dimension.new "minecraft:custom", Minecraft::NBT::CompoundTag.new({
    "min_y"  => Minecraft::NBT::IntTag.new(-32_i32).as(Minecraft::NBT::Tag),
    "height" => Minecraft::NBT::IntTag.new(512_i32).as(Minecraft::NBT::Tag),
  })
end

private def loaded_empty_chunk(dimension : Rosegold::Dimension) : Rosegold::Chunk
  data = Minecraft::IO::Memory.new
  (dimension.world_height >> 4).times { Rosegold::Section.empty.write(data) }
  chunk = Rosegold::Chunk.new(0, 0, Minecraft::IO::Memory.new(data.to_slice), dimension)
  dimension.load_chunk(chunk)
  chunk
end

private def stone_state : UInt16
  Rosegold::MCData.default.blocks.find! { |block| block.id_str == "stone" }.min_state_id
end

private def oak_fence_state : UInt16
  Rosegold::MCData.default.blocks.find! { |block| block.id_str == "oak_fence" }.min_state_id
end

private def world_height_dimensions : Array({String, Rosegold::Dimension})
  [
    {"overworld", Rosegold::Dimension.new},
    {"Nether", Rosegold::Dimension.new_nether},
    {"End", Rosegold::Dimension.new_end},
    {"custom", custom_dimension},
  ]
end

Spectator.describe "world-height collision bounds" do
  it "does not create unloaded-block obstacles outside each dimension or at its empty ceiling" do
    world_height_dimensions.each do |_, dimension|
      loaded_empty_chunk(dimension)
      entity_aabb = Rosegold::Player::DEFAULT_AABB
      below = Rosegold::Vec3d.new(0.5, (dimension.min_y - 4).to_f64, 0.5)
      above = Rosegold::Vec3d.new(0.5, (dimension.min_y + dimension.world_height + 2).to_f64, 0.5)
      at_ceiling = Rosegold::Vec3d.new(0.5, (dimension.min_y + dimension.world_height - 1.8).to_f64, 0.5)
      feet_at_ceiling = Rosegold::Vec3d.new(0.5, (dimension.min_y + dimension.world_height).to_f64, 0.5)
      velocity = Rosegold::Vec3d.new(0.0, 0.2, 0.0)
      horizontal_velocity = Rosegold::Vec3d.new(0.2, 0.0, 0.0)

      expect(Rosegold::Physics.get_grown_obstacles(below, velocity, entity_aabb, dimension)).to be_empty
      expect(Rosegold::Physics.get_grown_obstacles(above, velocity, entity_aabb, dimension)).to be_empty
      expect(Rosegold::Physics.get_grown_obstacles(at_ceiling, velocity, entity_aabb, dimension)).to be_empty
      expect(Rosegold::Physics.get_grown_obstacles(feet_at_ceiling, horizontal_velocity, entity_aabb, dimension)).to be_empty

      below_movement, _below_velocity = Rosegold::Physics.predict_movement_collision(below, velocity, entity_aabb, dimension)
      above_movement, _above_velocity = Rosegold::Physics.predict_movement_collision(above, velocity, entity_aabb, dimension)
      ceiling_movement, _ceiling_velocity = Rosegold::Physics.predict_movement_collision(at_ceiling, velocity, entity_aabb, dimension)
      horizontal_movement, _horizontal_velocity = Rosegold::Physics.predict_movement_collision(feet_at_ceiling, horizontal_velocity, entity_aabb, dimension)
      expect(below_movement).to eq(velocity)
      expect(above_movement).to eq(velocity)
      expect(ceiling_movement).to eq(velocity)
      expect(horizontal_movement).to eq(horizontal_velocity)
    end
  end

  it "does not treat out-of-range positions as solid when no chunk is loaded" do
    world_height_dimensions.each do |_, dimension|
      entity_aabb = Rosegold::Player::DEFAULT_AABB
      far_below = Rosegold::Vec3d.new(0.5, (dimension.min_y - 4).to_f64, 0.5)
      far_above = Rosegold::Vec3d.new(0.5, (dimension.min_y + dimension.world_height + 2).to_f64, 0.5)
      velocity = Rosegold::Vec3d.new(0.0, 0.2, 0.0)

      expect(Rosegold::Physics.get_grown_obstacles(far_below, velocity, entity_aabb, dimension)).to be_empty
      expect(Rosegold::Physics.get_grown_obstacles(far_above, velocity, entity_aabb, dimension)).to be_empty
    end
  end

  it "finds real blocks at the first and last valid Y coordinates" do
    world_height_dimensions.each do |_, dimension|
      chunk = loaded_empty_chunk(dimension)
      first_y = dimension.min_y
      last_y = dimension.min_y + dimension.world_height - 1
      chunk.set_block_state(0, first_y, 0, stone_state)
      chunk.set_block_state(0, last_y, 0, stone_state)
      chunk.set_block_state(2, last_y, 0, oak_fence_state)

      entity_aabb = Rosegold::Player::DEFAULT_AABB
      first_start = Rosegold::Vec3d.new(0.5, (first_y + 1).to_f64, 0.5)
      last_start = Rosegold::Vec3d.new(0.5, (last_y - 2).to_f64, 0.5)
      down = Rosegold::Vec3d.new(0.0, -0.5, 0.0)
      up = Rosegold::Vec3d.new(0.0, 0.5, 0.0)

      expect(Rosegold::Physics.get_grown_obstacles(first_start, down, entity_aabb, dimension)).not_to be_empty
      last_obstacles = Rosegold::Physics.get_grown_obstacles(last_start, up, entity_aabb, dimension)
      expect(last_obstacles).not_to be_empty
      fence_start = Rosegold::Vec3d.new(2.5, (last_y - 1).to_f64, 0.5)
      fence_obstacles = Rosegold::Physics.get_grown_obstacles(fence_start, up, entity_aabb, dimension)
      expect(fence_obstacles.any? { |obstacle| obstacle.max.y > last_y + 1 }).to be_true

      first_movement, _first_velocity = Rosegold::Physics.predict_movement_collision(first_start, down, entity_aabb, dimension)
      last_movement, _last_velocity = Rosegold::Physics.predict_movement_collision(last_start, up, entity_aabb, dimension)
      landing_start = Rosegold::Vec3d.new(0.5, (last_y + 2).to_f64, 0.5)
      landing_velocity = Rosegold::Vec3d.new(0.0, -1.5, 0.0)
      landing_movement, _landing_velocity = Rosegold::Physics.predict_movement_collision(landing_start, landing_velocity, entity_aabb, dimension)
      expect(first_movement.y).to be > down.y
      expect(last_movement.y).to be < up.y
      expect(landing_movement.y).to be > landing_velocity.y
    end
  end

  it "still treats unloaded in-range blocks as solid" do
    dimension = Rosegold::Dimension.new
    start = Rosegold::Vec3d.new(0.5, 0.5, 0.5)
    obstacles = Rosegold::Physics.get_grown_obstacles(
      start, Rosegold::Vec3d.new(0.0, 0.0, 0.0), Rosegold::Player::DEFAULT_AABB, dimension)

    expect(obstacles).not_to be_empty
  end

  it "considers space outside the world collision-free while retaining in-range collision checks" do
    dimension = custom_dimension
    client = Rosegold::Client.new("localhost", offline: {uuid: "test", username: "test"})
    client.dimension_for_collision_test = dimension
    physics = Rosegold::Physics.new(client)
    chunk = loaded_empty_chunk(dimension)
    first_y = dimension.min_y
    last_y = dimension.min_y + dimension.world_height - 1
    chunk.set_block_state(0, first_y, 0, stone_state)
    chunk.set_block_state(0, last_y, 0, stone_state)

    expect(physics.no_collision_for_test?(Rosegold::AABBd.new(0.4, (first_y - 2).to_f64, 0.4, 0.6, (first_y - 1).to_f64, 0.6))).to be_true
    expect(physics.no_collision_for_test?(Rosegold::AABBd.new(0.4, (last_y + 2).to_f64, 0.4, 0.6, (last_y + 3).to_f64, 0.6))).to be_true
    expect(physics.no_collision_for_test?(Rosegold::AABBd.new(0.4, first_y.to_f64, 0.4, 0.6, (first_y + 0.5).to_f64, 0.6))).to be_false
    expect(physics.no_collision_for_test?(Rosegold::AABBd.new(0.4, last_y.to_f64, 0.4, 0.6, (last_y + 0.5).to_f64, 0.6))).to be_false
  end

  it "returns nil for Chunk reads below its first section and above its last section" do
    dimension = custom_dimension
    chunk = loaded_empty_chunk(dimension)
    first_y = dimension.min_y
    after_last_y = dimension.min_y + dimension.world_height
    chunk.set_block_state(0, first_y, 0, stone_state)
    chunk.set_block_state(0, after_last_y - 1, 0, oak_fence_state)

    expect(chunk.block_state(0, first_y - 1, 0)).to be_nil
    expect(chunk.block_state(0, after_last_y, 0)).to be_nil
    expect(chunk.block_state(0, first_y, 0)).to eq(stone_state)
    expect(chunk.block_state(0, after_last_y - 1, 0)).to eq(oak_fence_state)
  end
end
