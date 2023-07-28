require "./event"

struct Int32
  def ticks
    1.second / 20
  end

  def tick
    ticks
  end
end

class Rosegold::Event::Tick < Rosegold::Event
end
