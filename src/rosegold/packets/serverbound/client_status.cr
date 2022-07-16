require "./packet"

# Respawn: action=0
class Rosegold::Serverbound::ClientStatus < Rosegold::Serverbound::Packet
  PACKET_ID = 0x04_u8

  property \
    action : UInt8

  def initialize(
    @action : UInt8 = 0
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write action
    end
  end
end
