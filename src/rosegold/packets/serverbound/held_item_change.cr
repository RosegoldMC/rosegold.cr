require "../packet"

class Rosegold::Serverbound::HeldItemChange < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x25_u8

  property hotbar_nr : UInt8

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt8); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write_full hotbar_nr.to_u16
    end.to_slice
  end
end
