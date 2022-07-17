class Rosegold::Clientbound::UpdateHealth < Rosegold::Clientbound::Packet
  property \
    health : Float32,
    food : UInt32,
    saturation : Float32

  def initialize(@health, @food, @saturation)
  end

  def self.read(packet)
    self.new(
      packet.read_float,
      packet.read_var_int,
      packet.read_float
    )
  end

  def callback(client)
    Log.debug { "health=#{health/2}❤ food=#{food*5}% saturation=#{saturation}" }
    # TODO: update health/food/saturation
    # TODO: check death
  end
end
