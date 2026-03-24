require "./event"

class Rosegold::Event::HealthChanged < Rosegold::Event
  getter old_health : Float32
  getter health : Float32
  getter food : UInt32
  getter saturation : Float32

  def initialize(@old_health, @health, @food, @saturation); end
end
