require "./event"

class Rosegold::Event::PlayerPositionUpdate < Rosegold::Event
  getter position : Vec3d
  getter look : Look

  def initialize(@position : Vec3d, @look : Look)
  end
end
