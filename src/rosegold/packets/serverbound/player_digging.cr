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
    @location : Vec3i,
    @face : BlockFace
  ); end

  def self.start(location, face)
    self.new(Status.Start, location, face)
  end

  def self.cancel(location, face)
    self.new(Status.Cancel, location, face)
  end

  def self.finish(location, face)
    self.new(Status.Finish, location, face)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write status.value
      buffer.write_bit_location location
      buffer.write face.value
    end.to_slice
  end
end
