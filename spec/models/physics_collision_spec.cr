require "../spec_helper"
require "../../src/rosegold/control/physics"
require "../../src/rosegold/world/aabb"
require "../../src/rosegold/world/vec3"

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
