require "./packet"

class Rosegold::Serverbound::PlayerNoMovement < Rosegold::Serverbound::Packet
  PACKET_ID = 0x14_u8

  property? on_ground : Bool

  def initialize(@on_ground); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write on_ground?
    end
  end
end
