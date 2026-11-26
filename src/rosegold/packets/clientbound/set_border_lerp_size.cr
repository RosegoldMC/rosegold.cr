require "../packet"

class Rosegold::Clientbound::SetBorderLerpSize < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x52_u32,
    773_u32 => 0x57_u32,
    774_u32 => 0x57_u32,
    775_u32 => 0x59_u32,
    776_u32 => 0x59_u32,
    777_u32 => 0x5b_u32,
  })

  getter old_size : Float64
  getter new_size : Float64
  getter duration : Int64

  def initialize(@old_size, @new_size, @duration); end

  def self.read(packet)
    old_size = packet.read_double
    new_size = packet.read_double
    new(old_size, new_size, packet.read_var_long.unsafe_as(Int64))
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write old_size
      buffer.write new_size
      buffer.write duration
    end.to_slice
  end

  def callback(client)
    client.dimension.world_border.lerp(old_size, new_size, duration, client.protocol_version)
  end
end
