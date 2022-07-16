require "./packet"

class Rosegold::Serverbound::PlayerLook < Rosegold::Serverbound::Packet
  PACKET_ID = 0x13_u8

  property \
    yaw_deg : Float32,
    pitch_deg : Float32,
    on_ground : Bool

  def initialize(@yaw_deg, @pitch_deg, @on_ground); end

  def self.new(look_deg : LookDeg, on_ground)
    self.new(look_deg.yaw, look_deg.pitch, on_ground)
  end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write_var_int PACKET_ID
      buffer.write yaw_deg
      buffer.write pitch_deg
      buffer.write on_ground
    end
  end
end
