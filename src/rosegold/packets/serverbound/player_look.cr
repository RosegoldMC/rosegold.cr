require "../packet"

class Rosegold::Serverbound::PlayerLook < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x13_u8

  property \
    yaw : Float32,
    pitch : Float32
  property? \
    on_ground : Bool

  def initialize(@yaw, @pitch, @on_ground); end

  def self.new(look : Look, on_ground)
    self.new(look.yaw, look.pitch, on_ground)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write yaw
      buffer.write pitch
      buffer.write on_ground?
    end.to_slice
  end
end
