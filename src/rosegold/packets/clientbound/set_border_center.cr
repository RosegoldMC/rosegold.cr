require "../packet"

class Rosegold::Clientbound::SetBorderCenter < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x51_u32,
    773_u32 => 0x56_u32,
    774_u32 => 0x56_u32,
    775_u32 => 0x58_u32,
    776_u32 => 0x58_u32,
    777_u32 => 0x5a_u32,
  })

  getter center_x : Float64
  getter center_z : Float64

  def initialize(@center_x, @center_z); end

  def self.read(packet)
    new(packet.read_double, packet.read_double)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write center_x
      buffer.write center_z
    end.to_slice
  end

  def callback(client)
    client.dimension.world_border.set_center(center_x, center_z)
  end
end
