require "../packet"

class Rosegold::Serverbound::StatusRequest < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x00_u8

  def self.read(io)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
    end.to_slice
  end
end

Rosegold::ProtocolState::STATUS.register Rosegold::Serverbound::StatusRequest
