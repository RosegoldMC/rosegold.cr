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

  def self.callback(client)
    puts "Disconnected: #{reason}"
    exit 0
  end
end
