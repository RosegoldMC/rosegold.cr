require "../world/aabb"
require "../world/vec3"

module Rosegold::Raytrace
  # A ray aimed at a block's closest point lands on an edge/corner of its hitbox,
  # and look quantization can put the hit a hair outside the face. Tolerate that so
  # grazing hits register instead of being dropped (mirrors vanilla's inflated clip);
  # far smaller than the 1/16 gap between blocks, so it can't hit a neighbor.
  EDGE_EPSILON = 1e-4

  # Movement collision uses the opposite tolerance from block-aiming: the entity box is
  # shrunk inward by 1e-7 on the perpendicular axes (matching vanilla VoxelShape.collideX),
  # so a surface the entity merely *touches* — e.g. the floor it stands flush on, or the
  # next floor block coplanar with its feet — does not impede perpendicular motion. Without
  # this the bot wall-sticks on the top face it stands on (top slabs, full-block floors).
  MOVE_EPSILON = 1e-7

  private def self.within?(value : Float64, lo : Float64, hi : Float64, strict : Bool) : Bool
    if strict
      lo + MOVE_EPSILON <= value && value <= hi - MOVE_EPSILON
    else
      lo - EDGE_EPSILON <= value && value <= hi + EDGE_EPSILON
    end
  end

  struct Ray
    getter start : Vec3d, delta : Vec3d

    def initialize(@start : Vec3d, @delta : Vec3d); end
  end

  struct Result
    getter intercept : Vec3d, box_nr : Int32, face : BlockFace

    def initialize(@intercept : Vec3d, @box_nr : Int32, @face : BlockFace); end
  end

  # `strict` selects movement-collision tolerance (touching != colliding); leave false for
  # block-aiming, which wants the grazing tolerance.
  def self.raytrace(start : Vec3d, delta : Vec3d, boxes : Array(AABBd), strict : Bool = false) : Result?
    raytrace(Ray.new(start, delta), boxes, strict)
  end

  def self.raytrace(ray : Ray, boxes : Array(AABBd), strict : Bool = false) : Result?
    min_scalar = 1_f64
    min_result = nil

    if ray.delta.x < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.x, BlockFace::East, min_scalar, min_result, box_nr, strict)
      end
    end
    if ray.delta.x > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.x, BlockFace::West, min_scalar, min_result, box_nr, strict)
      end
    end
    if ray.delta.y < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.y, BlockFace::Top, min_scalar, min_result, box_nr, strict)
      end
    end
    if ray.delta.y > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.y, BlockFace::Bottom, min_scalar, min_result, box_nr, strict)
      end
    end
    if ray.delta.z < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.z, BlockFace::South, min_scalar, min_result, box_nr, strict)
      end
    end
    if ray.delta.z > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.z, BlockFace::North, min_scalar, min_result, box_nr, strict)
      end
    end

    min_result
  end

  # TODO: rename this helper
  private def self.better(
    ray : Ray, box : AABBd, plane_coord : Float64, face : BlockFace,
    min_scalar : Float64, min_result : Result?, box_nr : Int32, strict : Bool,
  ) : Tuple(Float64, Result?)
    intersect_plane(ray, box, plane_coord, face, strict).try do |scalar, hit|
      if scalar < min_scalar
        {scalar, Result.new(hit, box_nr, face)}
      else
        {min_scalar, min_result}
      end
    end || {min_scalar, min_result}
  end

  private def self.intersect_plane(
    ray : Ray, box : AABBd, plane_coord : Float64, face : BlockFace, strict : Bool,
  ) : Tuple(Float64, Vec3d)?
    delta_coord = ray.delta.axis(face)
    start_coord = ray.start.axis(face)
    return nil if delta_coord * delta_coord < 0.0000001 # ray parallel to plane
    scalar = (plane_coord - start_coord) / delta_coord
    return nil if !(0 <= scalar && scalar < 1) # plane too far behind/ahead of ray
    hit = ray.start + ray.delta * scalar
    return nil if face != BlockFace::East && face != BlockFace::West && !within?(hit.x, box.min.x, box.max.x, strict)
    return nil if face != BlockFace::Top && face != BlockFace::Bottom && !within?(hit.y, box.min.y, box.max.y, strict)
    return nil if face != BlockFace::South && face != BlockFace::North && !within?(hit.z, box.min.z, box.max.z, strict)
    {scalar, hit}
  end
end
