require "../world/aabb"
require "../world/vec3"

module Rosegold::Raytracing
  struct Ray
    getter start : Vec3d, delta : Vec3d

    def initialize(@start : Vec3d, @delta : Vec3d); end
  end

  struct RayTraceResult
    getter intercept : Vec3d, box_nr : Int32, face : BlockFace

    def initialize(@intercept : Vec3d, @box_nr : Int32, @face : BlockFace); end
  end

  def self.raytrace(start : Vec3d, delta : Vec3d, boxes : Array(AABBd))
    raytrace(Ray.new(start, delta), boxes)
  end

  def self.raytrace(ray : Ray, boxes : Array(AABBd)) : RayTraceResult?
    min_scalar = 1_f64
    min_result = nil

    if ray.delta.x < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.x, BlockFace::East, min_scalar, min_result, box_nr)
      end
    end
    if ray.delta.x > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.x, BlockFace::West, min_scalar, min_result, box_nr)
      end
    end
    if ray.delta.y < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.y, BlockFace::Top, min_scalar, min_result, box_nr)
      end
    end
    if ray.delta.y > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.y, BlockFace::Bottom, min_scalar, min_result, box_nr)
      end
    end
    if ray.delta.z < 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.max.z, BlockFace::South, min_scalar, min_result, box_nr)
      end
    end
    if ray.delta.z > 0
      boxes.each_with_index do |box, box_nr|
        min_scalar, min_result = better(ray, box, box.min.z, BlockFace::North, min_scalar, min_result, box_nr)
      end
    end

    min_result
  end

  # TODO: rename this helper
  private def self.better(
    ray : Ray, box : AABBd, plane_coord : Float64, face : BlockFace,
    min_scalar : Float64, min_result : RayTraceResult?, box_nr : Int32
  ) : Tuple(Float64, RayTraceResult?)
    intersect_plane(ray, box, plane_coord, face).try do |scalar, hit|
      if scalar < min_scalar
        {scalar, RayTraceResult.new(hit, box_nr, face)}
      else
        {min_scalar, min_result}
      end
    end || {min_scalar, min_result}
  end

  # ameba:disable Metrics/CyclomaticComplexity
  private def self.intersect_plane(
    ray : Ray, box : AABBd, plane_coord : Float64, face : BlockFace
  ) : Tuple(Float64, Vec3d)?
    delta_coord = ray.delta.axis(face)
    start_coord = ray.start.axis(face)
    return nil if delta_coord * delta_coord < 0.0000001 # ray parallel to plane
    scalar = (plane_coord - start_coord) / delta_coord
    return nil if !(0 <= scalar && scalar < 1) # plane too far behind/ahead of ray
    hit = ray.start + ray.delta * scalar
    return nil if face != BlockFace::East && face != BlockFace::West && !(box.min.x < hit.x && hit.x < box.max.x)
    return nil if face != BlockFace::Top && face != BlockFace::Bottom && !(box.min.y < hit.y && hit.y < box.max.y)
    return nil if face != BlockFace::South && face != BlockFace::North && !(box.min.z < hit.z && hit.z < box.max.z)
    {scalar, hit}
  end
end
