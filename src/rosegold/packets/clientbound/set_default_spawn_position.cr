require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::SetDefaultSpawnPosition < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x5A_u8, # MC 1.21.8,
  })

  property \
    location : Vec3i,
    angle : Float32

  def initialize(@location, @angle); end

  def self.read(packet)
    location = packet.read_bit_location
    angle = packet.read_float
    self.new(location, angle)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write location
      buffer.write angle
    end.to_slice
  end

  def callback(client)
    Log.debug { "Set default spawn position: #{location} angle: #{angle}°" }
    # Update client's spawn point if we track it
    # client.spawn_position = location
    # client.spawn_angle = angle
  end
end
