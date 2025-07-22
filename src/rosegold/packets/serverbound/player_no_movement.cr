require "../packet"

class Rosegold::Serverbound::PlayerNoMovement < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x14_u8, # MC 1.18
    767_u32 => 0x1F_u8, # MC 1.21
    769_u32 => 0x1F_u8, # MC 1.21.4,
    771_u32 => 0x20_u8, # MC 1.21.6,
    772_u32 => 0x20_u8, # MC 1.21.8,
  })

  property? on_ground : Bool
  property? pushing_against_wall : Bool = false

  def initialize(@on_ground, @pushing_against_wall = false); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      if Client.protocol_version >= 767_u32
        # MC 1.21+ format: Use bit field (0x01: on ground, 0x02: pushing against wall)
        flags = 0_u8
        flags |= 0x01_u8 if on_ground?
        flags |= 0x02_u8 if pushing_against_wall?
        buffer.write flags
      else
        # MC 1.18 format: Just boolean on_ground
        buffer.write on_ground?
      end
    end.to_slice
  end
end
