require "../packet"

class Rosegold::Clientbound::EncryptionRequest < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x01_u8, # MC 1.18
    767_u32 => 0x01_u8, # MC 1.21
    771_u32 => 0x01_u8, # MC 1.21.6
  })
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
    encryption_response = Serverbound::EncryptionResponse.new self, client.player.uuid.to_s, client.access_token

    client.send_packet! encryption_response

    client.connection.io = Minecraft::EncryptedTCPSocket.new \
      client.connection.io,
      "aes-128-cfb8",
      encryption_response.shared_secret,
      encryption_response.shared_secret
  end
end