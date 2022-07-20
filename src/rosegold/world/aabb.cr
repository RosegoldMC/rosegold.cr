require "./vec3"

# axis aligned bounding box
module Rosegold::AABB(T)
  getter min : Vec3(T), max : Vec3(T)

  def initialize(@min : Vec3(T), @max : Vec3(T)); end

  def offset(vec : Vec3(T)) : self
    self.class.new min + vec, max + vec
  end

  def offset(x : T, y : T, z : T) : self
    self.class.new min.plus(x, y, z), max.plus(x, y, z)
  end

  def grow(vec : Vec3(T)) : self
    self.class.new min - vec, max + vec
  end

  def grow(dx : T, dy : T, dz : T) : self
    self.class.new min.minus(dx, dy, dz), max.plus(dx, dy, dz)
  end

  def intersects?(other : AABB(T)) : Bool
    other.max.x > self.min.x &&
      other.min.x < self.max.x &&
      other.max.y > self.min.y &&
      other.min.y < self.max.y &&
      other.max.z > self.min.z &&
      other.min.z < self.max.z
  end

  def [](i) : Vec3(T)
    {min, max}[i]
  end
end

struct Rosegold::AABBf
  include Rosegold::AABB(Float32)

  def self.new(
    min_x : Float32, min_y : Float32, min_z : Float32,
    max_x : Float32, max_y : Float32, max_z : Float32
  )
    self.new(Vec3f.new(min_x, min_y, min_z), Vec3f.new(max_x, max_y, max_z))
  end

  # additional methods that "upgrade" to AABBd

  def +(vec : Vec3d) : AABBd
    AABBd.new min + vec, max + vec
  end

  def to_f64 : AABBd
    AABBd.new min.to_f64, max.to_f64
  end
end

struct Rosegold::AABBd
  include Rosegold::AABB(Float64)

  def self.new(
    min_x : Float64, min_y : Float64, min_z : Float64,
    max_x : Float64, max_y : Float64, max_z : Float64
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
