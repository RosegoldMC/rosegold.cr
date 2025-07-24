require "../packet"

class Rosegold::Serverbound::KeepAlive < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (these actually change between versions!)
  packet_ids({
    772_u32 => 0x1B_u8, # MC 1.21.8,
  })

  property keep_alive_id : Int64

  def initialize(@keep_alive_id : Int64); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full keep_alive_id
    end.to_slice
  end
end
