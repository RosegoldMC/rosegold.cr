require "./vec3"

# axis aligned bounding box
module Rosegold::AABB(T)
  def +(vec : Vec3(T)) : self
    self.class.new min + vec, max + vec
  end

  def &+(vec : Vec3(T)) : self
    self.class.new min + vec, max + vec
  end

  def grow(vec : Vec3(T)) : self
    self.class.new min - vec, max + vec
  end

  def grow(dx : T, dy : T, dz : T) : self
    self.class.new min.minus(dx, dy, dz), max.plus(dx, dy, dz)
  end

  def [](i) : Vec3(T)
    {min, max}[i]
  end
end

struct Rosegold::AABBf
  include Rosegold::AABB(Float32)

  getter min : Vec3f, max : Vec3f

  def initialize(@min : Vec3f, @max : Vec3f); end

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
end

struct Rosegold::AABBd
  include Rosegold::AABB(Float64)

  property min : Vec3d, max : Vec3d

  def initialize(@min : Vec3d, @max : Vec3d); end

  def self.new(
    min_x : Float64, min_y : Float64, min_z : Float64,
    max_x : Float64, max_y : Float64, max_z : Float64
  )
    self.new(Vec3d.new(min_x, min_y, min_z), Vec3d.new(max_x, max_y, max_z))
  end
end
