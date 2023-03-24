class Rosegold::Clientbound::Disconnect < Rosegold::Clientbound::Packet
  property \
    reason : String

  def initialize(@reason)
  end

  def self.read(packet)
    self.new(
      packet.read_var_string
    )
  end

  def callback(client)
    Log.info { "Disconnected: #{reason}" }
    client.state = Rosegold::State::Disconnected.new
  end
end
