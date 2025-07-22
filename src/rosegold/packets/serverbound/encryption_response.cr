require "http/client"
require "json"
require "../../../minecraft/digest"
require "../packet"

class Rosegold::Serverbound::EncryptionResponse < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (same across all versions)
  packet_ids({
    758_u32 => 0x01_u8, # MC 1.18
    767_u32 => 0x01_u8, # MC 1.21
    769_u32 => 0x01_u8, # MC 1.21.4,
    771_u32 => 0x01_u8, # MC 1.21.6,
    772_u32 => 0x01_u8, # MC 1.21.8,
  })

  class_getter state = Rosegold::ProtocolState::LOGIN

  property \
    encryption_request : Rosegold::Clientbound::EncryptionRequest,
    shared_secret : Bytes,
    uuid : String,
    access_token : String

  def initialize(
    @encryption_request : Rosegold::Clientbound::EncryptionRequest,
    @uuid : String,
    @access_token : String,
  )
    @shared_secret = Random::Secure.random_bytes(16)
  end

  def digest
    Minecraft::Digest.hexdigest do |digest|
      digest << encryption_request.server_id
      digest << shared_secret
      digest << encryption_request.public_key
    end
  end

  def send_join_request!
    response = send_join_request
    raise "Join Request Failed: #{response.inspect}" unless response.status_code == 204
  end

  private def send_join_request
    HTTP::Client.post(
      "https://sessionserver.mojang.com/session/minecraft/join",
      headers: HTTP::Headers{
        "Content-Type" => "application/json",
      },
      body: {
        "accessToken":     access_token,
        "selectedProfile": uuid,
        "serverId":        digest,
      }.to_json
    )
  end

  def write : Bytes
    send_join_request!

    OpenSSL::PKey::RSA.new(IO::Memory.new("-----BEGIN PUBLIC KEY-----\n" + Base64.encode(encryption_request.public_key) + "-----END PUBLIC KEY-----\n")).try do |key|
      Minecraft::IO::Memory.new.tap do |buffer|
        buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

        key.public_encrypt(shared_secret).try do |encrypted_secret|
          buffer.write encrypted_secret.size.to_u32
          buffer.write encrypted_secret
        end

        key.public_encrypt(encryption_request.verify_token).try do |encrypted_nonce|
          buffer.write encrypted_nonce.size.to_u32
          buffer.write encrypted_nonce
        end
      end.to_slice
    end
  end
end
