require "./event"

class Rosegold::Event::ContainerClosed < Rosegold::Event
  getter window_id : UInt32

  def initialize(@window_id); end
end
