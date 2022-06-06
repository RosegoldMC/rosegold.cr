class Rosegold::Clientbound::LoginDisconnect < Rosegold::Clientbound::Packet
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
    puts "Disconnected!"
    exit 0
  end
end
