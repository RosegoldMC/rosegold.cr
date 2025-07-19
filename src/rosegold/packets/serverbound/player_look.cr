require "../packet"

class Rosegold::Serverbound::PlayerLook < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x13_u8, # MC 1.18
    767_u32 => 0x13_u8, # MC 1.21
    771_u32 => 0x13_u8, # MC 1.21.6
  })

  property \
    yaw : Float32,
    pitch : Float32
  property? \
    on_ground : Bool

  def initialize(@yaw, @pitch, @on_ground); end

  def self.new(look : Look, on_ground)
    self.new(look.yaw, look.pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write yaw
      buffer.write pitch
      buffer.write on_ground?
    end.to_slice
  end
end