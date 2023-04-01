require "../packet"

class Rosegold::Serverbound::PlayerDigging < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x1A_u8

  property \
    status : UInt32,
    location : Vec3d,
    face : UInt8

  def initialize(
    @status : UInt32,
    @location : Vec3d,
    @face : UInt8
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write status
      buffer.write location
      buffer.write face
    end.to_slice
  end
end
