class Rosegold::Clientbound::PlayerPositionAndLook < Rosegold::Clientbound::Packet
  property \
    x : Float64,
    y : Float64,
    z : Float64,
    yaw : Float32,
    pitch : Float32,
    flags : UInt8?,
    teleport_id : UInt32,
    dismount_vehicle : Bool

  def initialize(@x, @y, @z, @yaw, @pitch, @flags, @teleport_id, @dismount_vehicle)
  end

  def self.read(packet)
    new(
      pp!(packet.read_double),
      pp!(packet.read_double),
      pp!(packet.read_double),
      pp!(packet.read_float),
      pp!(packet.read_float),
      pp!(packet.read_byte),
      pp!(packet.read_var_int),
      pp!(packet.read_bool)
    )
  end
end
