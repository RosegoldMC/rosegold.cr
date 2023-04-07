require "../packet"

class Rosegold::Serverbound::PlayerDigging < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x1A_u8

  enum Status
    Start; Cancel; Finish; DropHandFull; DropHandSingle; FinishUsingHand; SwapHands
  end

  property \
    status : Status,
    location : Vec3i,
    face : BlockFace

  def initialize(
    @status : Status,
    @location : Vec3i = Vec3i::ORIGIN,
    @face : BlockFace = :bottom
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write status.value
      buffer.write location
      buffer.write face.value
    end.to_slice
  end
end
