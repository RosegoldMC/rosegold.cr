require "../spec_helper"
require "../../src/rosegold/control/physics"
require "../../src/rosegold/world/aabb"
require "../../src/rosegold/world/vec3"

Spectator.describe "Sneak edge prevention (maybeBackOffFromEdge)" do
  # Platform: 3x1x3 blocks at y=0..1, x=0..3, z=0..3
  # Player half-width: 0.3 (AABB is 0.6 wide)
  # Grown obstacles (Minkowski sum) extend 0.3 past block edges
  # So ground coverage extends to x=3.3 from the x=2 block row
  #
  # maybeBackOffFromEdge checks if there's solid ground below the player
  # after proposed horizontal movement, and clamps movement if not.

  let(sneaking_aabb) { Rosegold::Player::SNEAKING_AABB }

  def raw_platform_blocks : Array(Rosegold::AABBd)
    blocks = [] of Rosegold::AABBd
    (0..2).each do |x|
      (0..2).each do |z_idx|
        blocks << Rosegold::AABBd.new(x.to_f64, 0.0, z_idx.to_f64, x.to_f64 + 1.0, 1.0, z_idx.to_f64 + 1.0)
      end
    end
    blocks
  end

  def grown_obstacles(entity_aabb : Rosegold::AABBf) : Array(Rosegold::AABBd)
    entity_aabb_d = entity_aabb.to_f64
    grow_aabb = entity_aabb_d * -1
    raw_platform_blocks.map(&.grow(grow_aabb))
  end

  # Simulate multiple physics ticks with sneak edge prevention applied.
  # When sneaking=true, calls Physics.maybe_back_off_from_edge before collision.
  def simulate_ticks(
    start : Rosegold::Vec3d,
    x_velocity : Float64,
    z_velocity : Float64,
    entity_aabb : Rosegold::AABBf,
    ticks : Int32,
    sneaking : Bool = false,
  ) : Rosegold::Vec3d
    obstacles = grown_obstacles(entity_aabb)
    blocks = raw_platform_blocks
    pos = start
    vel_y = -0.08 # gravity

    ticks.times do
      velocity = Rosegold::Vec3d.new(x_velocity, vel_y, z_velocity)

      if sneaking
        velocity = Rosegold::Physics.maybe_back_off_from_edge(pos, velocity, entity_aabb) do |test_aabb|
          blocks.none?(&.intersects?(test_aabb))
        end
      end

      movement, new_vel = Rosegold::Physics.predict_movement_collision(pos, velocity, obstacles)
      pos = pos + movement

      vertical_collided = (movement.y - velocity.y).abs > 1.0e-7
      if vertical_collided && velocity.y < 0
        vel_y = -0.08
      else
        vel_y = new_vel.y * 0.98 - 0.08
      end
    end
    pos
  end

  context "without sneaking" do
    it "player falls off edge after walking past ground coverage" do
      start = Rosegold::Vec3d.new(1.5, 1.0, 1.5)
      final_pos = simulate_ticks(start, 0.15, 0.0, sneaking_aabb, 20, sneaking: false)
      expect(final_pos.y).to be < 1.0
    end
  end

  context "with sneaking" do
    it "player should not fall off edge when walking toward it" do
      start = Rosegold::Vec3d.new(2.0, 1.0, 1.5)
      final_pos = simulate_ticks(start, 0.15, 0.0, sneaking_aabb, 20, sneaking: true)
      expect(final_pos.y).to eq 1.0
    end

    it "player should not fall off edge diagonally" do
      start = Rosegold::Vec3d.new(2.0, 1.0, 2.0)
      final_pos = simulate_ticks(start, 0.1, 0.1, sneaking_aabb, 20, sneaking: true)
      expect(final_pos.y).to eq 1.0
    end

    it "player should move freely away from edge when sneaking" do
      start = Rosegold::Vec3d.new(2.5, 1.0, 1.5)
      final_pos = simulate_ticks(start, -0.1, 0.0, sneaking_aabb, 2, sneaking: true)
      expect(final_pos.x).to be < start.x
      expect(final_pos.y).to be_close(1.0, 0.01)
    end

    it "player at center of platform should move normally when sneaking" do
      start = Rosegold::Vec3d.new(1.0, 1.0, 1.5)
      final_pos = simulate_ticks(start, 0.05, 0.0, sneaking_aabb, 3, sneaking: true)
      expect(final_pos.x).to be > start.x
      expect(final_pos.y).to eq 1.0
    end
  end
end
