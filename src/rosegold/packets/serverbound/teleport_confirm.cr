require "../packet"

class Rosegold::Serverbound::TeleportConfirm < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x00_u32, # MC 1.21.8
    774_u32 => 0x00_u32, # MC 1.21.11
    773_u32 => 0x00_u32, # MC 1.21.9
    775_u32 => 0x00_u32, # MC 26.1
    776_u32 => 0x00_u32, # MC 26.2
    777_u32 => 0x00_u32, # MC 26.3
  })

  property \
    teleport_id : UInt32,
    x : Float64 = 0.0,
    y : Float64 = 0.0,
    z : Float64 = 0.0,
    yaw : Float32 = 0.0_f32,
    pitch : Float32 = 0.0_f32

  def initialize(@teleport_id : UInt32, @x = 0.0, @y = 0.0, @z = 0.0, @yaw = 0.0_f32, @pitch = 0.0_f32); end

  def self.read(io)
    teleport_id = io.read_var_int
    if Client.protocol_version >= 777_u32
      new(teleport_id, io.read_double, io.read_double, io.read_double, io.read_float, io.read_float)
    else
      new(teleport_id)
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write teleport_id
      if Client.protocol_version >= 777_u32
        buffer.write x
        buffer.write y
        buffer.write z
        buffer.write yaw
        buffer.write pitch
      end
    end.to_slice
  end
end
