require "./packet"

class Rosegold::Serverbound::Status < Rosegold::Serverbound::Packet
  PACKET_ID = 0x00_u32

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
    end
  end
end
