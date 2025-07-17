require "./vec3"

# axis aligned bounding box
module Rosegold::AABB(T, V)
  getter min : V, max : V

  def initialize(min : V, max : V)
    @min = V.new(
      Math.min(min.x, max.x),
      Math.min(min.y, max.y),
      Math.min(min.z, max.z))
    @max = V.new(
      Math.max(min.x, max.x),
      Math.max(min.y, max.y),
      Math.max(min.z, max.z))
  end

  def offset(vec : V) : self
    self.class.new min + vec, max + vec
  end

  def offset(x : T, y : T, z : T) : self
    self.class.new min.plus(x, y, z), max.plus(x, y, z)
  end

  def grow(vec : V) : self
    self.class.new min - vec, max + vec
  end

  def grow(dx : T, dy : T, dz : T) : self
    self.class.new min.minus(dx, dy, dz), max.plus(dx, dy, dz)
  end

  def grow(aabb : AABB(T, V)) : self
    self.class.new min + aabb.min, max + aabb.max
  end

  def *(scalar : T) : self
    self.class.new min * scalar, max * scalar
  end

  def contains?(vec : V) : Bool
    (self.min.x < vec.x < self.max.x) &&
      (self.min.y < vec.y < self.max.y) &&
      (self.min.z < vec.z < self.max.z)
  end

  def intersects?(other : AABB(T, V)) : Bool
    other.max.x > self.min.x &&
      other.min.x < self.max.x &&
      other.max.y > self.min.y &&
      other.min.y < self.max.y &&
      other.max.z > self.min.z &&
      other.min.z < self.max.z
  end

  def ray_intersection(start : V, end_ : V) : Float64?
    direction = end_ - start
    t_min = Vec3d.new((self.min.x - start.x) / direction.x,
      (self.min.y - start.y) / direction.y,
      (self.min.z - start.z) / direction.z)

    t_max = Vec3d.new((self.max.x - start.x) / direction.x,
      (self.max.y - start.y) / direction.y,
      (self.max.z - start.z) / direction.z)

    t_min_x, t_max_x = [t_min.x, t_max.x].min, [t_min.x, t_max.x].max
    t_min_y, t_max_y = [t_min.y, t_max.y].min, [t_min.y, t_max.y].max
    t_min_z, t_max_z = [t_min.z, t_max.z].min, [t_min.z, t_max.z].max

    t_near = [t_min_x, t_min_y, t_min_z].max
    t_far = [t_max_x, t_max_y, t_max_z].min

    return nil if t_near > t_far
    return nil if t_far < 0

    t_near
  rescue e : ArgumentError
    nil
  end

  def [](i) : V
    {min, max}[i]
  end
end

struct Rosegold::AABBf
  include Rosegold::AABB(Float32, Vec3f)

  def self.new(
    min_x : Float32, min_y : Float32, min_z : Float32,
    max_x : Float32, max_y : Float32, max_z : Float32,
  )
    self.new(Vec3f.new(min_x, min_y, min_z), Vec3f.new(max_x, max_y, max_z))
  end

  # additional methods that "upgrade" to AABBd

  def +(vec : Vec3d) : AABBd
    AABBd.new min + vec, max + vec
  end

  def offset(vec : Vec3d) : AABBd
    AABBd.new min + vec, max + vec
  end

  def to_f64 : AABBd
    AABBd.new min.to_f64, max.to_f64
  end
end

struct Rosegold::AABBd
  include Rosegold::AABB(Float64, Vec3d)

  def self.new(
    min_x : Float64, min_y : Float64, min_z : Float64,
    max_x : Float64, max_y : Float64, max_z : Float64,
  )
    self.new(Vec3d.new(min_x, min_y, min_z), Vec3d.new(max_x, max_y, max_z))
  end

  def self.containing_all(*aabbs : AABBd) : AABBd
    self.new(
      aabbs.min_by(&.min.x).min.x,
      aabbs.min_by(&.min.y).min.y,
      aabbs.min_by(&.min.z).min.z,
      aabbs.max_by(&.max.x).max.x,
      aabbs.max_by(&.max.y).max.y,
      aabbs.max_by(&.max.z).max.z,
    )
  end
end
