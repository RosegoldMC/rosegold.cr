class Rosegold::Clientbound::ChangeDifficulty < Rosegold::Clientbound::Packet
  property \
    difficulty : UInt8?,
    difficulty_locked : Bool

  def initialize(@difficulty, @difficulty_locked)
  end

  def self.read(packet)
    self.new(
      packet.read_byte,
      packet.read_bool
    )
  end

  def callback(client)
    client.state = State::Play.new
  end
end
