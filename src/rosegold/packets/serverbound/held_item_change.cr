require "./packet"

class Rosegold::Serverbound::HeldItemChange < Rosegold::Serverbound::Packet
  PACKET_ID = 0x25_u8

  property hotbar_nr : UInt8

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt8); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write_full hotbar_nr.to_u16
    end
  end
end
