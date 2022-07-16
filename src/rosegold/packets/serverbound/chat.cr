require "./packet"

class Rosegold::Serverbound::Chat < Rosegold::Serverbound::Packet
  PACKET_ID = 0x03_u8

  property \
    message : String

  def initialize(
    @message : String
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write message
    end
  end
end
