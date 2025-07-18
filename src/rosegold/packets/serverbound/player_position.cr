require "../packet"

class Rosegold::Serverbound::PlayerPosition < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (changes between versions!)
  packet_ids({
    758_u32 => 0x11_u8, # MC 1.18
    767_u32 => 0x14_u8, # MC 1.21 - CHANGED!
    771_u32 => 0x14_u8, # MC 1.21.6
  })

  property \
    x : Float64,
    y : Float64,
    z : Float64
  property? \
    on_ground : Bool

  def initialize(@x, @y, @z, @on_ground); end

  def self.new(feet : Vec3d, on_ground)
    self.new(feet.x, feet.y, feet.z, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write x
      buffer.write y
      buffer.write z
      buffer.write on_ground?
    end.to_slice
  end
end
