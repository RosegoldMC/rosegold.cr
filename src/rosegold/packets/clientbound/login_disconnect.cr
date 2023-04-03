require "../packet"

class Rosegold::Clientbound::LoginDisconnect < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x00_u8
  class_getter state = Rosegold::ProtocolState::LOGIN

  property reason : String

  def initialize(@reason); end

  def self.read(packet)
    self.new(packet.read_var_string)
  end

  def callback(client)
    client.connection.disconnect reason
  end
end
