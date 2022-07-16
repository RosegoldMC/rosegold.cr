require "./packet"

class Rosegold::Serverbound::CloseWindow < Rosegold::Serverbound::Packet
  PACKET_ID = 0x09_u32

  property \
    window_id : UInt16

  def initialize(
    @window_id : UInt16
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write window_id
    end
  end
end
