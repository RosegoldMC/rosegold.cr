require "../packet"

class Rosegold::Serverbound::StatusPing < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x01_u8
  class_getter state = Rosegold::ProtocolState::STATUS

  property ping_id : Int64

  def initialize(@ping_id); end

  def self.read(packet)
    self.new(packet.read_long)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write_full ping_id
    end.to_slice
  end
end
