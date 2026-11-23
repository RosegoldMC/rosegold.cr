require "../packet"

class Rosegold::Clientbound::SetBorderSize < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x53_u32,
    773_u32 => 0x58_u32,
    774_u32 => 0x58_u32,
    775_u32 => 0x5a_u32,
    776_u32 => 0x5a_u32,
    777_u32 => 0x5c_u32,
  })

  getter size : Float64

  def initialize(@size); end

  def self.read(packet)
    new(packet.read_double)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write size
    end.to_slice
  end

  def callback(client)
    client.dimension.world_border.resize(size)
  end
end
