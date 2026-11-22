require "../spec_helper"
require "../../src/rosegold/control/physics"
require "../../src/rosegold/world/aabb"
require "../../src/rosegold/world/vec3"
require "../../src/rosegold/world/player"

Spectator.describe "Physics horizontal movement on a flush floor" do
  # Regression for a freeze observed on a real server: in a 2-tall corridor with a top-slab
  # floor, the bot rests with feet exactly at the floor's top face (feet.y == 63.0). The
  # floor block one step ahead is coplanar with the feet; with inclusive collision bounds
  # its side face wrongly registers as a wall and horizontal velocity is zeroed, and the
  # surrounding ceiling/wall geometry blocks the 0.6 auto-step from masking it. Vanilla
  # (VoxelShape.collideX) shrinks the entity box inward by 1e-7 on the perpendicular axes,
  # so a merely-touched surface never impedes perpendicular motion. Block coordinates and
  # the start position are taken verbatim from the captured stuck frame; without the fix
  # `movement.x` comes back 0.0 instead of the commanded -0.13.
  it "does not wall-stick on the slab floor it stands on" do
    grow_aabb = Rosegold::Player::DEFAULT_AABB.to_f64 * -1
    full = Rosegold::AABBf.new(0_f32, 0_f32, 0_f32, 1_f32, 1_f32, 1_f32)
    top_slab = Rosegold::AABBf.new(0_f32, 0.5_f32, 0_f32, 1_f32, 1_f32, 1_f32)
    chest_a = Rosegold::AABBf.new(0.0625_f32, 0_f32, 0.0625_f32, 1_f32, 0.875_f32, 0.9375_f32)
    chest_b = Rosegold::AABBf.new(0_f32, 0_f32, 0.0625_f32, 0.9375_f32, 0.875_f32, 0.9375_f32)

    blocks = [
      {4489, 62, -15890, top_slab}, {4489, 62, -15889, full}, {4489, 62, -15888, full},
      {4489, 63, -15889, full}, {4489, 63, -15888, chest_a}, {4489, 64, -15889, full}, {4489, 64, -15888, chest_a},
      {4489, 65, -15892, full}, {4489, 65, -15891, full}, {4489, 65, -15890, full}, {4489, 65, -15889, full},
      {4490, 62, -15892, top_slab}, {4490, 62, -15891, top_slab}, {4490, 62, -15890, top_slab}, {4490, 62, -15889, full}, {4490, 62, -15888, full},
      {4490, 63, -15889, full}, {4490, 63, -15888, chest_b}, {4490, 64, -15889, full}, {4490, 64, -15888, chest_b},
      {4490, 65, -15892, full}, {4490, 65, -15891, full}, {4490, 65, -15890, full}, {4490, 65, -15889, full},
      {4491, 62, -15890, top_slab}, {4491, 62, -15889, full}, {4491, 62, -15888, full},
      {4491, 63, -15889, full}, {4491, 63, -15888, chest_a}, {4491, 64, -15889, full}, {4491, 64, -15888, chest_a},
      {4491, 65, -15892, full}, {4491, 65, -15891, full}, {4491, 65, -15890, full}, {4491, 65, -15889, full},
      {4492, 62, -15890, top_slab}, {4492, 62, -15889, full}, {4492, 62, -15888, full},
      {4492, 63, -15889, full}, {4492, 63, -15888, chest_b}, {4492, 64, -15889, full}, {4492, 64, -15888, chest_b},
      {4492, 65, -15889, full},
      {4493, 62, -15890, top_slab}, {4493, 62, -15889, full}, {4493, 62, -15888, full},
      {4493, 63, -15889, full}, {4493, 64, -15889, full}, {4493, 65, -15889, full},
    ]
    obstacles = blocks.map do |(x, y, z, shape)|
      shape.to_f64.offset(x.to_f64, y.to_f64, z.to_f64).grow(grow_aabb)
    end

    start = Rosegold::Vec3d.new(4491.300000011921, 63.0, -15889.500000052583)
    velocity = Rosegold::Vec3d.new(-0.13000001203703704, -0.0784, -8.347977526169494e-9)

    movement, _ = Rosegold::Physics.predict_movement_collision(start, velocity, obstacles)

    expect(movement.x).to be < -0.1
  end
end

Spectator.describe "Physics collision with block above head" do
  it "AABB.contains? should not consider player inside block when at exact boundary" do
    # This is the core bug: when player feet are at Y=147.0 exactly,
    # and there's a ground block at [147, 148), the new asymmetric boundary
    # logic (>= min, < max) considers the player "inside" the ground block.
    # This causes the block to be rejected as an obstacle, leading to stuck movement.

    # Ground block occupies Y=147 to Y=148
    ground_block = Rosegold::AABBd.new(
      Rosegold::Vec3d.new(0.0, 147.0, 0.0),
      Rosegold::Vec3d.new(1.0, 148.0, 1.0)
    )

    # Player feet at exactly Y=147.0 (on the ground)
    player_feet = Rosegold::Vec3d.new(0.5, 147.0, 0.5)

    # With the buggy asymmetric boundaries (>= min, < max):
    # 147.0 >= 147.0 = true, 147.0 < 148.0 = true
    # So player is considered "inside" the ground block (WRONG!)
    #
    # With correct strict boundaries (< on both sides):
    # 147.0 < 147.0 = false
    # So player is NOT inside the ground block (CORRECT!)

    # This test will FAIL with the current buggy implementation
    # The player should NOT be considered inside the ground block
    expect(ground_block.contains?(player_feet)).to be_false
  end

  it "AABB.contains? should work correctly for positions strictly inside block" do
    # A position clearly inside the block should be detected as contained
    block = Rosegold::AABBd.new(
      Rosegold::Vec3d.new(0.0, 147.0, 0.0),
      Rosegold::Vec3d.new(1.0, 148.0, 1.0)
    )

    inside_position = Rosegold::Vec3d.new(0.5, 147.5, 0.5)

    expect(block.contains?(inside_position)).to be_true
  end

  it "player head at ceiling boundary should not be considered inside ceiling block" do
    # Player head at Y=148.8, ceiling block at [149, 150)
    # Player head should NOT be considered inside the ceiling
    ceiling_block = Rosegold::AABBd.new(
      Rosegold::Vec3d.new(0.0, 149.0, 0.0),
      Rosegold::Vec3d.new(1.0, 150.0, 1.0)
    )

    player_head = Rosegold::Vec3d.new(0.5, 148.8, 0.5)

    expect(ceiling_block.contains?(player_head)).to be_false
  end
end

Spectator.describe "Physics stepping under a ceiling" do
  def step_obstacles(ceiling_bottom : Float64?, step_top = 0.5)
    grow_aabb = Rosegold::Player::DEFAULT_AABB.to_f64 * -1
    boxes = [
      Rosegold::AABBd.new(0.0, -1.0, 0.0, 1.0, 0.0, 1.0),
      Rosegold::AABBd.new(1.0, -1.0, 0.0, 2.0, step_top, 1.0),
    ]
    ceiling_bottom.try do |bottom|
      boxes << Rosegold::AABBd.new(1.0, bottom, 0.0, 2.0, bottom + 1.0, 1.0)
    end
    boxes.map &.grow(grow_aabb)
  end

  def walk(obstacles)
    start = Rosegold::Vec3d.new(0.6, 0.0, 0.5)
    velocity = Rosegold::Vec3d.new(0.13, -0.0784, 0.0)
    Rosegold::Physics.predict_movement_collision(start, velocity, obstacles)
  end

  it "steps up a slab when the ceiling clears the stepped height but not a full 0.6 lift" do
    movement, _ = walk step_obstacles(2.35)
    expect(movement.x).to be_within(1e-6).of(0.13)
    expect(movement.y).to be_within(1e-6).of(0.5)
  end

  it "still steps without a ceiling" do
    movement, _ = walk step_obstacles(nil)
    expect(movement.x).to be_within(1e-6).of(0.13)
    expect(movement.y).to be_within(1e-6).of(0.5)
  end

  it "is blocked when the ceiling leaves no room at the stepped height" do
    movement, _ = walk step_obstacles(2.2)
    expect(movement.x).to be < 0.1
    expect(movement.y).to be_within(1e-6).of(0.0)
  end

  it "is blocked by a step taller than the maximum lift" do
    movement, _ = walk step_obstacles(nil, 0.7)
    expect(movement.x).to be < 0.1
  end
end

Spectator.describe "Physics stepping from farmland onto a slab under a ceiling" do
  def walk_onto_slab(aabb, floor_top, slab_top, ceiling_bottom)
    grow_aabb = aabb.to_f64 * -1
    boxes = [
      Rosegold::AABBd.new(0.0, -100.0, 0.0, 1.0, floor_top, 1.0),
      Rosegold::AABBd.new(1.0, -100.0, 0.0, 2.0, slab_top, 1.0),
      Rosegold::AABBd.new(1.0, ceiling_bottom, 0.0, 2.0, ceiling_bottom + 1.0, 1.0),
    ].map &.grow(grow_aabb)
    start = Rosegold::Vec3d.new(0.6, floor_top, 0.5)
    Rosegold::Physics.predict_movement_collision(start, Rosegold::Vec3d.new(0.13, -0.0784, 0.0), boxes)
  end

  it "stands onto a flush top slab with 2.0 clearance above it" do
    movement, _ = walk_onto_slab(Rosegold::Player::DEFAULT_AABB, 0.9375, 1.0, 3.0)
    expect(movement.x).to be_within(1e-6).of(0.13)
    expect(movement.y).to be_within(1e-6).of(0.0625)
  end

  it "stays blocked standing when the slab clearance is under the player height" do
    movement, _ = walk_onto_slab(Rosegold::Player::DEFAULT_AABB, 0.9375, 1.0, 2.7)
    expect(movement.x).to be < 0.1
  end

  it "sneaks onto a bottom slab with 1.5 clearance above it" do
    movement, _ = walk_onto_slab(Rosegold::Player::SNEAKING_AABB, -60.0625, -59.5, -58.0)
    expect(movement.x).to be_within(1e-6).of(0.13)
    expect(movement.y).to be_within(1e-6).of(0.5625)
  end

  it "stays blocked sneaking when the slab clearance is under 1.5" do
    movement, _ = walk_onto_slab(Rosegold::Player::SNEAKING_AABB, -60.0625, -59.5, -58.1)
    expect(movement.x).to be < 0.1
  end

  it "keeps ground progress instead of stepping into a diagonal wall" do
    grow_aabb = Rosegold::Player::SNEAKING_AABB.to_f64 * -1
    obstacles = [
      Rosegold::AABBd.new(0.0, 0.0, 0.0, 1.0, 0.9375, 1.0),
      Rosegold::AABBd.new(1.0, 1.0, 0.0, 2.0, 1.5, 1.0),
      Rosegold::AABBd.new(1.0, 3.0, 0.0, 2.0, 4.0, 1.0),
      Rosegold::AABBd.new(1.0, 1.0, 1.0, 2.0, 2.0, 2.0),
    ].map &.grow(grow_aabb)
    start = Rosegold::Vec3d.new(0.68, 0.9375, 0.68)
    velocity = Rosegold::Vec3d.new(0.022, -0.0784, 0.022)
    wall = obstacles.last

    movement, _ = Rosegold::Physics.predict_movement_collision(start, velocity, obstacles)

    ground_progress = Rosegold::Vec3d.new(wall.min.x - start.x, 0, velocity.z).length
    expect(wall.contains?(start + movement)).to be_false
    expect(movement.with_y(0).length).to be_within(1e-6).of(ground_progress)
    expect(movement.y).to be_within(1e-6).of(0.0)
  end
end
