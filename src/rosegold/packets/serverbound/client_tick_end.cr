require "../packet"

class Rosegold::Serverbound::ClientTickEnd < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x0C_u8,
  })

  class_getter state = Rosegold::ProtocolState::PLAY

  def initialize
  end

  def self.read(packet)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end
end
