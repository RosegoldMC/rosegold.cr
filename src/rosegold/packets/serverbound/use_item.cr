require "./packet"

class Rosegold::Serverbound::UseItem < Rosegold::Serverbound::Packet
  PACKET_ID = 0x2f_u32

  property \
    hand : UInt8

  # 0: main hand, 1: off hand
  def initialize(
    @hand : UInt8 = 0
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write hand
    end
  end
end
