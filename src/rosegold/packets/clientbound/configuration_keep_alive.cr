require "../packet"

class Rosegold::Clientbound::ConfigurationKeepAlive < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    767_u32 => 0x04_u8, # MC 1.21
    769_u32 => 0x04_u8, # MC 1.21.4,
    771_u32 => 0x04_u8, # MC 1.21.6,
    772_u32 => 0x04_u8, # MC 1.21.8,
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
