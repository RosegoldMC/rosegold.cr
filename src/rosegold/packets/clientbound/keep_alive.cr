require "../packet"

class Rosegold::Clientbound::KeepAlive < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x26_u32, # MC 1.21.8
    774_u32 => 0x2B_u32, # MC 1.21.11
    775_u32 => 0x2C_u32, # MC 26.1
  })

  property keep_alive_id : Int64

  def initialize(@keep_alive_id); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full keep_alive_id
    end.to_slice
  end

  def callback(client)
    client.queue_packet Serverbound::KeepAlive.new keep_alive_id
  end
end
