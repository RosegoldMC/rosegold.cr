require "./event"

class Rosegold::Event::SneakChanged < Rosegold::Event
  getter? sneaking : Bool

  def initialize(@sneaking : Bool); end
end
