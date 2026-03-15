require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::SetDefaultSpawnPosition < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x5A_u32, # MC 1.21.8
    774_u32 => 0x5F_u32, # MC 1.21.11
  })

  property \
    dimension : String = "",
    location : Vec3i,
    yaw : Float32,
    pitch : Float32 = 0_f32

  def initialize(@location, @yaw, @dimension = "", @pitch = 0_f32); end

  def self.read(packet)
    if Client.protocol_version >= 774_u32
      dimension = packet.read_var_string
      location = packet.read_bit_location
      yaw = packet.read_float
      pitch = packet.read_float
    else
      dimension = ""
      location = packet.read_bit_location
      yaw = packet.read_float
      pitch = 0_f32
    end
    self.new(location, yaw, dimension, pitch)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      if Client.protocol_version >= 774_u32
        buffer.write dimension
        buffer.write location
        buffer.write yaw
        buffer.write pitch
      else
        buffer.write location
        buffer.write yaw
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Set default spawn position: #{location} yaw: #{yaw}° pitch: #{pitch}°" }
  end
end
