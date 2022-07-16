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
    client.log_info { "Disconnected: #{reason}" }
    exit 0
  end
end
