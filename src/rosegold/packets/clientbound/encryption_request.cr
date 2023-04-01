require "../packet"

class Rosegold::Clientbound::EncryptionRequest < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x01_u8
  class_getter state = Rosegold::ProtocolState::LOGIN

  property \
    server_id : String,
    public_key : String,
    verify_token : Bytes

  def initialize(@server_id, @public_key, @verify_token); end

  def self.read(packet)
    self.new(
      packet.read_var_string,
      packet.read_var_string,
      packet.read_var_bytes
    )
  end

  def callback(client)
    encryption_response = Serverbound::EncryptionResponse.new self

    client.send_packet! encryption_response

    client.connection.io = Minecraft::EncryptedTCPSocket.new \
      client.connection.io,
      "aes-128-cfb8",
      encryption_response.shared_secret,
      encryption_response.shared_secret
  end
end
