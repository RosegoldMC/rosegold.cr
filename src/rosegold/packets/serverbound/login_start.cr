require "./packet"

class Rosegold::Serverbound::LoginStart < Rosegold::Serverbound::Packet
  PACKET_ID = 0x00_u8

  property \
    username : String

  def initialize(
    @username : String
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write username
    end
  end
end
