require "../packet"

class Rosegold::Serverbound::PlayerInput < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x2A_u8, # MC 1.21.8 (Player Input)
  })

  # Player Input flags from protocol documentation
  @[Flags]
  enum Flag : UInt8
    Forward  = 0x01
    Backward = 0x02
    Left     = 0x04
    Right    = 0x08
    Jump     = 0x10
    Sneak    = 0x20
    Sprint   = 0x40
  end

  property flags : Flag

  def initialize(@flags : Flag = Flag::None)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write flags.value
    end.to_slice
  end
end
