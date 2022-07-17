class Rosegold::Clientbound::EncryptionRequest < Rosegold::Clientbound::Packet
  property \
    server_id : String,
    public_key : String,
    verify_token : Bytes

  def initialize(@server_id, @public_key, @verify_token)
  end

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

    client.io = Minecraft::EncryptedTCPSocket.new \
      client.io,
      "aes-128-cfb8",
      encryption_response.shared_secret,
      encryption_response.shared_secret
  end
end
