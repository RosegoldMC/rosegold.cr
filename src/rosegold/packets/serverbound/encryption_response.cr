require "http/client"
require "json"
require "./packet"

class Rosegold::Serverbound::EncryptionResponse < Rosegold::Serverbound::Packet
  PACKET_ID = 0x01_u8

  UUID         = ENV["UUID"]
  ACCESS_TOKEN = ENV["ACCESS_TOKEN"]

  property \
    encryption_request : Rosegold::Clientbound::EncryptionRequest,
    shared_secret : Bytes

  def initialize(
    @encryption_request : Rosegold::Clientbound::EncryptionRequest
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
    raise "Join Request Failed" unless send_join_request
  end

  private def send_join_request
    HTTP::Client.post(
      "https://sessionserver.mojang.com/session/minecraft/join",
      headers: HTTP::Headers{
        "Content-Type" => "application/json",
      },
      body: {
        "accessToken":     ACCESS_TOKEN,
        "selectedProfile": UUID,
        "serverId":        digest,
      }.to_json
    ).status_code == 204
  end

  def to_packet : Minecraft::IO
    send_join_request!

    OpenSSL::PKey::RSA.new(IO::Memory.new("-----BEGIN PUBLIC KEY-----\n" + Base64.encode(encryption_request.public_key) + "-----END PUBLIC KEY-----\n")).try do |key|
      Minecraft::IO::Memory.new.tap do |buffer|
        buffer.write PACKET_ID

        key.public_encrypt(shared_secret).try do |encrypted_secret|
          buffer.write encrypted_secret.size.to_u32
          buffer.write encrypted_secret
        end

        key.public_encrypt(encryption_request.verify_token).try do |encrypted_nonce|
          buffer.write encrypted_nonce.size.to_u32
          buffer.write encrypted_nonce
        end
      end
    end
  end
end
