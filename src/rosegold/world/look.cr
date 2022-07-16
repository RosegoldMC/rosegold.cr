# The unit circle of yaw on the XZ-plane has 0° at (0, 1), 90° at (-1, 0), 180° at (0, -1) and 270° at (1, 0).
#
# Yaw is not clamped to between 0 and 360 degrees; any number is valid, including negative numbers and numbers greater than 360.
#
# Pitch 0 is looking straight ahead, -90° is looking straight up, and 90° is looking straight down.
#
# There are an infinite number of "down"/"up" looks with different yaw; use e.g. `NORTH.down`.
abstract struct Rosegold::Look(T)
  property yaw, pitch

  def initialize(@yaw : T, @pitch : T)
  end

  def initialize(yaw_pitch : Tuple(T, T))
    @yaw, @pitch = yaw_pitch
  end

  def -
    self.new(-x, -y)
  end

  def -(look : self)
    self.new(x - look.x, y - look.y, z - look.z)
  end

  def +(look : self)
    self.new(x + look.x, y + look.y, z + look.z)
  end
end

struct Rosegold::LookRad < Rosegold::Look(Float32)
  SOUTH = self.new(0, 0)
  WEST  = self.new(PI/2, 0)
  NORTH = self.new(PI, 0)
  EAST  = self.new(PI*3/2, 0)

  def down
    self.new(yaw, PI/2)
  end

  def up
    self.new(yaw, -PI/2)
  end

  def to_deg
    LookDeg.new(yaw*360/TAU, pitch*360/TAU)
  end
end

struct Rosegold::LookDeg < Rosegold::Look(Float32)
  SOUTH = self.new(0, 0)
  WEST  = self.new(90, 0)
  NORTH = self.new(180, 0)
  EAST  = self.new(270, 0)

  def down
    self.new(yaw, 90)
  end

  def up
    self.new(yaw, -90)
  end

  def to_rad
    LookRad.new(yaw*TAU/360, pitch*TAU/360)
  end
end
