require "../../world/look"
require "../packet"

# Player Rotation packet - sent by server to update only the player's rotation
class Rosegold::Clientbound::PlayerRotation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x42_u8, # MC 1.21.8
  })

  property \
    yaw : Float32,
    pitch : Float32

  def initialize(@yaw, @pitch)
  end

  def self.read(packet)
    yaw = packet.read_float
    pitch = packet.read_float
    self.new(yaw, pitch)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write yaw
      io.write pitch
    end.to_slice
  end

  def callback(client)
    player = client.player
    player.look = Look.new(yaw, pitch)

    Log.debug { "Player rotation updated: yaw=#{yaw}, pitch=#{pitch}" }
  end
end
