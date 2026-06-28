require "../../spec_helper"

Spectator.describe Rosegold::Raytrace do
  # Unit cube at the origin.
  let(box) { Rosegold::AABBd.new(0.0, 0.0, 0.0, 1.0, 1.0, 1.0) }

  describe ".raytrace" do
    it "registers a ray that grazes an edge of the box" do
      # Eye outside on x and z, level on y; aimed straight at the (x=0,z=0) edge.
      start = Rosegold::Vec3d.new(-1.0, 0.5, -1.0)
      delta = Rosegold::Vec3d.new(2.0, 0.0, 2.0)
      result = Rosegold::Raytrace.raytrace(start, delta, [box])
      expect(result).not_to be_nil
    end

    it "registers a ray that grazes a corner of the box" do
      # Eye outside on all three axes, aimed at the (0,0,0) corner.
      start = Rosegold::Vec3d.new(-1.0, -1.0, -1.0)
      delta = Rosegold::Vec3d.new(2.0, 2.0, 2.0)
      result = Rosegold::Raytrace.raytrace(start, delta, [box])
      expect(result).not_to be_nil
    end

    it "still hits a face squarely" do
      start = Rosegold::Vec3d.new(-1.0, 0.5, 0.5)
      delta = Rosegold::Vec3d.new(2.0, 0.0, 0.0)
      result = Rosegold::Raytrace.raytrace(start, delta, [box])
      expect(result).not_to be_nil
    end

    it "still misses a box the ray never reaches" do
      start = Rosegold::Vec3d.new(-1.0, 5.0, 0.5)
      delta = Rosegold::Vec3d.new(2.0, 0.0, 0.0)
      result = Rosegold::Raytrace.raytrace(start, delta, [box])
      expect(result).to be_nil
    end
  end
end
