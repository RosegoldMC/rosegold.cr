# The unit circle of yaw on the XZ-plane has 0° at (0, 1), 90° at (-1, 0), 180° at (0, -1) and 270° at (1, 0).
#
# Yaw is not clamped to between 0° and 360°; any number is valid, including negative numbers and numbers greater than 360°.
#
# Pitch 0 is looking straight ahead, -90° is looking straight up, and 90° is looking straight down.
#
# There are an infinite number of "down"/"up" looks with different yaw; use e.g. `NORTH.down`.
struct Rosegold::Look
  SOUTH = self.new(0, 0)
  WEST  = self.new(90, 0)
  NORTH = self.new(180, 0)
  EAST  = self.new(270, 0)

  getter yaw_deg : Float32
  getter pitch_deg : Float32

  def yaw_rad
    yaw_deg * Math.TAU / 360
  end

  def pitch_rad
    pitch_deg * Math.TAU / 360
  end

  private def initialize(@yaw_deg : Float32, @pitch_deg : Float32); end

  def self.from_deg(yaw_deg : Float32, pitch_deg : Float32)
    while yaw_deg < 0
      yaw_deg += 4*360
    end
    self.new(yaw_deg % 360, pitch_deg)
  end

  def self.from_rad(yaw_rad : Float32, pitch_rad : Float32)
    self.from_deg yaw_rad * 360 / Math.TAU, pitch_rad * 360 / Math.TAU
  end

  def self.from_vec(vec : Vec3d | Vec3f)
    yaw_rad = Math.atan2(-vec.x, vec.z)
    ground_distance = Math.sqrt(vec.x * vec.x + vec.z * vec.z)
    pitch_rad = -Math.atan2(vec.y, ground_distance)
    return Look.from_rad(yaw_rad.as_f32, pitch_rad.as_f32)
  end

  def inspect(io)
    io << "#<Look yaw=" << yaw_deg << "° pitch=" << pitch_deg << "°>"
  end

  def down
    self.new(yaw_deg, 90)
  end

  def up
    self.new(yaw_deg, -90)
  end

  def with_yaw_deg(yaw_deg : Float32)
    Look.from_deg(yaw_deg, pitch_deg)
  end

  def with_pitch_deg(pitch_deg : Float32)
    Look.from_deg(yaw_deg, pitch_deg)
  end

  def to_vec3
    Vec3d.new(
      -Math.cos(pitch_rad) * Math.sin(yaw_rad),
      -Math.sin(pitch_rad),
      Math.cos(pitch_rad) * Math.cos(yaw_rad)
    )
  end
end
