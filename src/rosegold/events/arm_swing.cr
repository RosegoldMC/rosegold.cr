require "./event"

class Rosegold::Event::ArmSwing < Rosegold::Event
  getter hand : Hand

  def initialize(@hand : Hand = Hand::MainHand); end
end
