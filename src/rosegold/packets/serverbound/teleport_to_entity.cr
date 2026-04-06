require "../packet"

class Rosegold::Serverbound::TeleportToEntity < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x3D_u32, # MC 1.21.8
    774_u32 => 0x3D_u32, # MC 1.21.11
    775_u32 => 0x40_u32, # MC 26.1
  })
  class_getter state = ProtocolState::PLAY

  property target_uuid : UUID

  def initialize(@target_uuid : UUID)
  end

  def self.read(packet)
    target_uuid = packet.read_uuid
    self.new(target_uuid)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write target_uuid
    end.to_slice
  end
end
