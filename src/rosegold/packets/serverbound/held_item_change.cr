require "./packet"

class Rosegold::Serverbound::HeldItemChange < Rosegold::Serverbound::Packet
  PACKET_ID = 0x25_u32

  property \
    hotbar_nr : UInt16

  # `hotbar_nr` ranges from 0 to 8
  def initialize(
    @hotbar_nr : UInt16
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write hotbar_nr
    end
  end
end
