require "../packet"

class Rosegold::Clientbound::LoginDisconnect < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x00_u8

  property reason : String

  def initialize(@reason); end

  def self.read(packet)
    self.new(packet.read_var_string)
  end

  def callback(client)
    client.connection.try &.disconnect reason
  end
end

Rosegold::ProtocolState::LOGIN.register Rosegold::Clientbound::LoginDisconnect
