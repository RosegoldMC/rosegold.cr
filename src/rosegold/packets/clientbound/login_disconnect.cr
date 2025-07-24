require "../packet"

class Rosegold::Clientbound::LoginDisconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x00_u8, # MC 1.21.8,
  })
  class_getter state = Rosegold::ProtocolState::LOGIN

  property reason : Chat

  def initialize(@reason); end

  def self.read(packet)
    self.new Chat.from_json packet.read_var_string
  end

  def callback(client)
    client.connection.disconnect reason
  end
end
