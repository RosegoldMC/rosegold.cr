require "../packet"

class Rosegold::Clientbound::InitializeBorder < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x25_u32,
    773_u32 => 0x2a_u32,
    774_u32 => 0x2a_u32,
    775_u32 => 0x2b_u32,
    776_u32 => 0x2b_u32,
    777_u32 => 0x2c_u32,
  })

  getter center_x : Float64
  getter center_z : Float64
  getter old_size : Float64
  getter new_size : Float64
  getter duration : Int64
  getter absolute_max_size : Int32
  getter warning_blocks : Int32
  getter warning_time : Int32

  def initialize(@center_x, @center_z, @old_size, @new_size, @duration,
                 @absolute_max_size, @warning_blocks, @warning_time); end

  def self.read(packet)
    center_x = packet.read_double
    center_z = packet.read_double
    old_size = packet.read_double
    new_size = packet.read_double
    duration = packet.read_var_long.unsafe_as(Int64)
    absolute_max_size = packet.read_var_int.unsafe_as(Int32)
    warning_blocks = packet.read_var_int.unsafe_as(Int32)
    warning_time = packet.read_var_int.unsafe_as(Int32)
    new(center_x, center_z, old_size, new_size, duration,
      absolute_max_size, warning_blocks, warning_time)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write center_x
      buffer.write center_z
      buffer.write old_size
      buffer.write new_size
      buffer.write duration
      buffer.write absolute_max_size
      buffer.write warning_blocks
      buffer.write warning_time
    end.to_slice
  end

  def callback(client)
    client.dimension.world_border.initialize_bounds(
      center_x, center_z, old_size, new_size, duration,
      absolute_max_size, client.protocol_version)
  end
end
