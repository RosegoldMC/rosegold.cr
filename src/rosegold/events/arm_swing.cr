require "./event"

class Rosegold::Event::ArmSwing < Rosegold::Event
  getter hand : Hand
  getter animation : DataComponents::SwingAnimation?

  def initialize(@hand : Hand = Hand::MainHand, @animation : DataComponents::SwingAnimation? = nil); end
end
