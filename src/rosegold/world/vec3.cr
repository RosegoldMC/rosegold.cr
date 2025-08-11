module Rosegold::Vec3(T)
  getter x : T, y : T, z : T

  def initialize(@x : T, @y : T, @z : T); end

  def west(len : T = 1) : self
    self.class.new x - len, y, z
  end

  def east(len : T = 1) : self
    self.class.new x + len, y, z
  end

  def down(len : T = 1) : self
    self.class.new x, y - len, z
  end

  def up(len : T = 1) : self
    self.class.new x, y + len, z
  end

  def north(len : T = 1) : self
    self.class.new x, y, z - len
  end

  def south(len : T = 1) : self
    self.class.new x, y, z + len
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

  def -(other : self) : self
    self.class.new x - other.x, y - other.y, z - other.z
  end

  def minus(dx : T, dy : T, dz : T) : self
    self.class.new x - dx, y - dy, z - dz
  end

  def +(other : self) : self
    self.class.new x + other.x, y + other.y, z + other.z
  end

  def plus(dx : T, dy : T, dz : T) : self
    self.class.new x + dx, y + dy, z + dz
  end

  def *(other : T) : self
    self.class.new x * other, y * other, z * other
  end

  def &*(other : T) : self
    self.class.new x * other, y * other, z * other
  end

  def /(other : T) : self
    self.class.new x / other, y / other, z / other
  end

  def map(block : T -> T) : self
    self.class.new block.call(x), block.call(y), block.call(z)
  end

  def ==(other : Vec3(T)) : Bool
    x.round(4) == other.x.round(4) && y.round(4) == other.y.round(4) && z.round(4) == other.z.round(4)
  end

  def normed : self
    self / length
  end

  def rounded : self
    self.class.new x.round_away, y.round_away, z.round_away
  end

  def to_f32 : Vec3f
    Vec3f.new x.to_f32, y.to_f32, z.to_f32
  end

  def to_f64 : Vec3d
    Vec3d.new x.to_f64, y.to_f64, z.to_f64
  end

  def block : Vec3i
    Vec3i.new x.floor.to_i32, y.floor.to_i32, z.floor.to_i32
  end

  def floored : Vec3d
    Vec3d.new x.floor, y.floor, z.floor
  end

  # Useful for standing centered on a block.
  def centered_floor : Vec3d
    floored.plus 0.5, 0, 0.5
  end

  # Useful for getting the center of a block.
  def centered_3d : Vec3d
    floored.plus 0.5, 0.5, 0.5
  end

  def with_length(length : Float64) : Vec3d
    my_length = self.len
    if my_length === 0
      self.to_f64 * 0
    else
      self.to_f64 * (length / my_length)
    end
  end

  def len_sq : T
    x*x + y*y + z*z
  end

  def length : Float64
    Math.sqrt len_sq
  end

  def dist_sq(other : self) : T
    (self - other).len_sq
  end

  def dist(other : self) : T
    (self - other).length
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
    dist_sq(other) < closer_than * closer_than
  end

  def [](i : Number) : T
    {x, y, z}[i]
  end

  def axis(face : BlockFace) : T
    case face
    when BlockFace::West, BlockFace::East
      x
    when BlockFace::Bottom, BlockFace::Top
      y
    when BlockFace::North, BlockFace::South
      z
    else raise "Invalid BlockFace #{face}"
    end
  end

  def with_axis(face : BlockFace, value : T) : self
    case face
    when BlockFace::West, BlockFace::East
      self.class.new value, y, z
    when BlockFace::Bottom, BlockFace::Top
      self.class.new x, value, z
    when BlockFace::North, BlockFace::South
      self.class.new x, y, value
    else raise "Invalid BlockFace #{face}"
    end
  end

  def +(other : BlockFace) : Vec3d
    centered_3d + other.to_vec3d(0.5)
  end

  def to_s(io, sep = ", ")
    io << x << sep << y << sep << z
  end

  def join(sep = ", ")
    "#{x}#{sep}#{y}#{sep}#{z}"
  end

  def inspect(io)
    io << "#<Vec3 " << x << "," << y << "," << z << ">"
  end
end

struct Rosegold::Vec3i
  include Rosegold::Vec3(Int32)

  ORIGIN = self.new 0, 0, 0

  def block
    self
  end
end

struct Rosegold::Vec3f
  include Rosegold::Vec3(Float32)

  ORIGIN = self.new 0, 0, 0

  def to_f32
    self
  end

  # additional methods that "upgrade" to Vec3d

  def -(other : Vec3d) : Vec3d
    Vec3d.new x - other.x, y - other.y, z - other.z
  end

  def +(other : Vec3d) : Vec3d
    Vec3d.new x + other.x, y + other.y, z + other.z
  end
end

struct Rosegold::Vec3d
  include Rosegold::Vec3(Float64)

  ORIGIN = self.new 0, 0, 0

  def to_f64
    self
  end
end

enum BlockFace
  # order matters for packet serialization
  Bottom; Top; North; South; West; East

  def +(other : Vec3d | Vec3i) : Vec3d
    other.centered_3d + to_vec3d(0.5)
  end

  def to_vec3d(len : Float64 = 0.5) : Vec3d
    case self
    when BlockFace::West
      Vec3d.new -len, 0, 0
    when BlockFace::East
      Vec3d.new len, 0, 0
    when BlockFace::Bottom
      Vec3d.new 0, -len, 0
    when BlockFace::Top
      Vec3d.new 0, len, 0
    when BlockFace::North
      Vec3d.new 0, 0, -len
    when BlockFace::South
      Vec3d.new 0, 0, len
    else raise "Invalid BlockFace #{self}"
    end
  end
end
