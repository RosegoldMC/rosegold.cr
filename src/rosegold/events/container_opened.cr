require "./event"

class Rosegold::Event::ContainerOpened < Rosegold::Event
  getter window_type : UInt32
  getter title : String
  getter menu : Menu

  def initialize(@window_type, @title, @menu); end
end
