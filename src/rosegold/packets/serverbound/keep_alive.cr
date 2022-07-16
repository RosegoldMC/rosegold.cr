require "./packet"

class Rosegold::Serverbound::KeepAlive < Rosegold::Serverbound::Packet
  PACKET_ID = 0x0f_u8

  property \
    keep_alive_id : UInt64

  def initialize(
    @keep_alive_id : UInt64
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write_full keep_alive_id
    end
  end
end
