require "./packet"

class Rosegold::Serverbound::PlayerDigging < Rosegold::Serverbound::Packet
  PACKET_ID = 0x1A_u8

  property \
    status : UInt32,
    location : Vec3d,
    face : UInt8

  def initialize(
    @status : UInt32,
    @location : Vec3d,
    @face : UInt8
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write status
      buffer.write location
      buffer.write face
    end
  end
end
