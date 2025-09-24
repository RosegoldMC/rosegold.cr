require "../packet"

class Rosegold::Clientbound::EncryptionRequest < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x01_u8, # MC 1.21.8,
  })
  class_getter state = Rosegold::ProtocolState::LOGIN

  property \
    server_id : String,
    public_key : String,
    verify_token : Bytes,
    should_authenticate : Bool? = false

  def initialize(@server_id, @public_key, @verify_token, @should_authenticate = false); end

  def self.read(packet)
    self.new(
      packet.read_var_string,
      packet.read_var_string,
      packet.read_var_bytes,
      packet.read_bool
    )
  end

  def callback(client)
    encryption_response = Serverbound::EncryptionResponse.new self, client.player.uuid.to_s, client.access_token

    client.send_packet! encryption_response

    client.connection.io = Minecraft::EncryptedTCPSocket.new \
      client.connection.io,
      "aes-128-cfb8",
      encryption_response.shared_secret,
      encryption_response.shared_secret
  end
end
