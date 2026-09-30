# The unit circle of yaw on the XZ-plane has 0° at (0, 1), 90° at (-1, 0), 180° at (0, -1) and 270° at (1, 0).
#
# Yaw is not clamped to between 0° and 360°; any number is valid, including negative numbers and numbers greater than 360°.
#
# Pitch 0 is looking straight ahead, -90° is looking straight up, and 90° is looking straight down.
#
# There are an infinite number of "down"/"up" looks with different yaw; use e.g. `NORTH.down`.
struct Rosegold::Look
  # Faces positive Z on the horizontal plane.
  SOUTH = self.new(0, 0)
  # Faces negative X on the horizontal plane.
  WEST = self.new(90, 0)
  # Faces negative Z on the horizontal plane.
  NORTH = self.new(180, 0)
  # Faces positive X on the horizontal plane.
  EAST = self.new(270, 0)

  # Horizontal facing angle in degrees.
  getter yaw : Float32
  # Vertical facing angle in degrees; negative looks up and positive looks down.
  getter pitch : Float32

  # Creates a direction from yaw and pitch in degrees. Angles are stored as given.
  def initialize(@yaw : Float32, @pitch : Float32); end

  # Normalizes a yaw angle to the half-open range -180 through 180 degrees.
  # Returns 0 for `NaN` or infinite input.
  def self.wrap_yaw(yaw : Float32) : Float32
    return 0.0_f32 if yaw.nan? || yaw.infinite?

    wrapped = yaw.remainder(360.0_f32)
    return wrapped - 360.0_f32 if wrapped >= 180.0_f32
    return wrapped + 360.0_f32 if wrapped < -180.0_f32

    wrapped
  end

  # The yaw angle in radians.
  def yaw_rad
    yaw * Math::TAU / 360
  end

  # The pitch angle in radians.
  def pitch_rad
    pitch * Math::TAU / 360
  end

  # Returns a copy with *yaw* in degrees and the existing pitch.
  def with_yaw(yaw : Float32)
    Look.new(yaw, pitch)
  end

  # Returns a copy with a Float64 *yaw* converted to Float32.
  def with_yaw(yaw : Float64)
    with_yaw yaw.to_f32
  end

  # Returns a copy with *pitch* in degrees and the existing yaw.
  def with_pitch(pitch : Float32)
    Look.new(yaw, pitch)
  end

  # Returns a copy with a Float64 *pitch* converted to Float32.
  def with_pitch(pitch : Float64)
    with_pitch pitch.to_f32
  end

  # Returns a copy looking downward by *angle* degrees while retaining yaw.
  def down(angle : Float32 = 90)
    Look.new(yaw, angle)
  end

  # Returns a copy looking upward by *angle* degrees while retaining yaw.
  def up(angle : Float32 = 90)
    Look.new(yaw, -angle)
  end

  # Converts this direction to a unit world-space vector.
  def to_vec3
    Vec3d.new(
      -Math.cos(pitch_rad) * Math.sin(yaw_rad),
      -Math.sin(pitch_rad),
      Math.cos(pitch_rad) * Math.cos(yaw_rad)
    )
  end

  # Builds a direction that points along *vec*.
  def self.from_vec(vec : Vec3d | Vec3f)
    yaw_rad = Math.atan2(-vec.x, vec.z)
    ground_distance = Math.sqrt(vec.x * vec.x + vec.z * vec.z)
    pitch_rad = -Math.atan2(vec.y, ground_distance)

    Look.from_rad(yaw_rad.to_f32, pitch_rad.to_f32)
  end

  # Builds a direction from yaw and pitch in radians.
  def self.from_rad(yaw_rad : Float32, pitch_rad : Float32)
    yaw = yaw_rad * 360 / Math::TAU
    pitch = pitch_rad * 360 / Math::TAU
    Look.new yaw.to_f32, pitch.to_f32
  end

  # Writes a compact yaw/pitch representation for debugging.
  def inspect(io)
    io << "#<Look yaw=" << yaw << "° pitch=" << pitch << "°>"
  end
end
