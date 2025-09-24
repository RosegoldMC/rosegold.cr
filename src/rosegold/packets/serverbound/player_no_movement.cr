require "../packet"

class Rosegold::Serverbound::PlayerNoMovement < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x20_u8, # MC 1.21.8,
  })

  property? on_ground : Bool
  property? pushing_against_wall : Bool = false

  def initialize(@on_ground, @pushing_against_wall = false); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      # MC 1.21+ format: Use bit field (0x01: on ground, 0x02: pushing against wall)
      flags = 0_u8
      flags |= 0x01_u8 if on_ground?
      flags |= 0x02_u8 if pushing_against_wall?
      buffer.write flags
    end.to_slice
  end
end
