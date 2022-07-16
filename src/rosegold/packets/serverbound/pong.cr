require "./packet"

class Rosegold::Serverbound::Pong < Rosegold::Serverbound::Packet
  PACKET_ID = 0x1d_u32

  property \
    ping_id : Int32

  def initialize(
    @ping_id : Int32
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write ping_id
    end
  end
end
