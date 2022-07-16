abstract struct Rosegold::Vec3(T)
  property x, y, z

  def initialize(@x : T, @y : T, @z : T)
  end

  def initialize(xyz : Tuple(T, T, T))
    @x, @y, @z = xyz
  end

  def -
    self.new(-x, -y, -z)
  end

  def -(vec : self)
    self.new(x - vec.x, y - vec.y, z - vec.z)
  end

  def +(vec : self)
    self.new(x + vec.x, y + vec.y, z + vec.z)
  end

  def *(scalar : T)
    self.new(x * scalar, y * scalar, z * scalar)
  end

  def &*(scalar : T)
    self.new(x * scalar, y * scalar, z * scalar)
  end

  def /(scalar : T)
    self.new(x / scalar, y / scalar, z / scalar)
  end
end

struct Rosegold::Vec3f < Rosegold::Vec3(Float32)
  ORIGIN = self.new 0, 0, 0
end

struct Rosegold::Vec3d < Rosegold::Vec3(Float64)
  ORIGIN = self.new 0, 0, 0
end
