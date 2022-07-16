require "./packet"

class Rosegold::Serverbound::TeleportConfirm < Rosegold::Serverbound::Packet
  PACKET_ID = 0x00_u32

  property \
    teleport_id : UInt32

  def initialize(
    @teleport_id : UInt32
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write teleport_id
    end
  end
end
