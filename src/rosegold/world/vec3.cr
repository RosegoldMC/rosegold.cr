module Rosegold::Vec3(T)
  def west(len : T = 1) : self
    self.class.new x - 1, y, z
  end

  def east(len : T = 1) : self
    self.class.new x + 1, y, z
  end

  def down(len : T = 1) : self
    self.class.new x, y - 1, z
  end

  def up(len : T = 1) : self
    self.class.new x, y + 1, z
  end

  def north(len : T = 1) : self
    self.class.new x, y, z - 1
  end

  def south(len : T = 1) : self
    self.class.new x, y, z + 1
  end

  def with_x(x : T) : self
    self.class.new x, y, z
  end

  def with_y(y : T) : self
    self.class.new x, y, z
  end

  def with_z(z : T) : self
    self.class.new x, y, z
  end

  def - : self
    self.class.new -x, -y, -z
  end

  def -(vec : self) : self
    self.class.new x - vec.x, y - vec.y, z - vec.z
  end

  def minus(dx : T, dy : T, dz : T) : self
    self.class.new x - dx, y - dy, z - dz
  end

  def +(vec : self) : self
    self.class.new x + vec.x, y + vec.y, z + vec.z
  end

  def plus(dx : T, dy : T, dz : T) : self
    self.class.new x + dx, y + dy, z + dz
  end

  def *(scalar : T) : self
    self.class.new x * scalar, y * scalar, z * scalar
  end

  def &*(scalar : T) : self
    self.class.new x * scalar, y * scalar, z * scalar
  end

  def /(scalar : T) : self
    self.class.new x / scalar, y / scalar, z / scalar
  end

  def map(block : T -> T) : self
    self.class.new block.call(x), block.call(y), block.call(z)
  end

  def normed : self
    self / len
  end

  def rounded : self
    self.class.new x.round_away, y.round_away, z.round_away
  end

  def floored : self
    self.class.new x.floor, y.floor, z.floor
  end

  # Useful for standing centered on a block.
  def centered_floor : self
    floored.plus 0.5, 0, 0.5
  end

  # Useful for getting the center of a block.
  def centered_3d : self
    floored.plus 0.5, 0.5, 0.5
  end

  def with_length(length : T) : self
    my_length = this.len
    if (my_length === 0)
      self * 0
    else
      self * (length / my_length)
    end
  end

  def len_sq : T
    x*x + y*y + z*z
  end

  def len : T
    Math.sqrt len_sq
  end

  def dist_sq(other : self) : T
    (self - other).len_sq
  end

  def dist(other : self) : T
    (self - other).len
  end

  # Ignores y difference.
  def xz_dist(other : self) : T
    dx = x - other.x
    dz = z - other.z
    Math.sqrt(dx * dx + dz * dz)
  end

  # The point on the line through `start` and `start+direction` that is closest to `self`.
  # See also `#projected_factor_along_line`.
  def project_onto_line(
    start : self,
    direction : self
  ) : self
    steps = projected_factor_along_line start, direction
    start + steps * direction
  end

  # How far to move from `start` in `direction` units to arrive at the point that is closest to `self`.
  # See also `#project_onto_line`.
  def projected_factor_along_line(
    start : self,
    direction : self
  ) : T
    (x - start.x) * direction.x +
      (y - start.y) * direction.y +
      (z - start.z) * direction.z
  end

  def almost_eq(other : self, closer_than = 0.01) : Bool
    return dist_sq(other) < closer_than * closer_than
  end

  def [](i) : T
    {x, y, z}[i]
  end

  def to_s(io)
    io << "#{x}, #{y}, #{z}"
  end

  def inspect(io)
    io << "#<Vec3 " << x << "," << y << "," << z << ">"
  end
end

struct Rosegold::Vec3f
  include Rosegold::Vec3(Float32)

  ORIGIN = self.new 0, 0, 0

  getter x : Float32, y : Float32, z : Float32

  def initialize(@x : Float32, @y : Float32, @z : Float32); end

  # additional methods that "upgrade" to Vec3d

  def -(vec : Vec3d) : Vec3d
    Vec3d.new x - vec.x, y - vec.y, z - vec.z
  end

  def &-(vec : Vec3d) : Vec3d
    Vec3d.new x - vec.x, y - vec.y, z - vec.z
  end

  def +(vec : Vec3d) : Vec3d
    Vec3d.new x + vec.x, y + vec.y, z + vec.z
  end

  def &+(vec : Vec3d) : Vec3d
    Vec3d.new x + vec.x, y + vec.y, z + vec.z
  end

  def to_f64 : Vec3d
    Vec3d.new x, y, z
  end
end

struct Rosegold::Vec3d
  include Rosegold::Vec3(Float64)

  ORIGIN = self.new 0, 0, 0

  getter x : Float64, y : Float64, z : Float64

  def initialize(@x : Float64, @y : Float64, @z : Float64); end

  def to_f32 : Vec3f
    Vec3f.new x, y, z
  end
end
