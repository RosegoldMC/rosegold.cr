# axis aligned bounding box
struct Rosegold::AABB
  property \
    x_min : Float32, y_min : Float32, z_min : Float32,
    x_max : Float32, y_max : Float32, z_max : Float32

  def initialize(@x_min, @y_min, @z_min, @x_max, @y_max, @z_max); end
end
