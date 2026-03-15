require "../../world/look"
require "../packet"

# Player Rotation packet - sent by server to update only the player's rotation
class Rosegold::Clientbound::PlayerRotation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x42_u32, # MC 1.21.8
    774_u32 => 0x47_u32, # MC 1.21.11
  })

  property \
    yaw : Float32,
    pitch : Float32
  property? \
    relative_yaw : Bool = false,
    relative_pitch : Bool = false

  def initialize(@yaw, @pitch, @relative_yaw = false, @relative_pitch = false)
  end

  def self.read(packet)
    if Client.protocol_version >= 774_u32
      yaw = packet.read_float
      relative_yaw = packet.read_bool
      pitch = packet.read_float
      relative_pitch = packet.read_bool
      self.new(yaw, pitch, relative_yaw, relative_pitch)
    else
      yaw = packet.read_float
      pitch = packet.read_float
      self.new(yaw, pitch)
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      if Client.protocol_version >= 774_u32
        io.write yaw
        io.write relative_yaw
        io.write pitch
        io.write relative_pitch
      else
        io.write yaw
        io.write pitch
      end
    end.to_slice
  end

  def callback(client)
    player = client.player
    new_yaw = relative_yaw? ? player.look.yaw + yaw : yaw
    new_pitch = relative_pitch? ? player.look.pitch + pitch : pitch
    player.look = Look.new(new_yaw, new_pitch)

    Log.debug { "Player rotation updated: yaw=#{new_yaw}, pitch=#{new_pitch}" }
  end
end
