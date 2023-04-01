require "../packet"

class Rosegold::Serverbound::Chat < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x03_u8

  property message : String

  def initialize(@message : String); end

  def self.read(io)
    self.new(io.read_var_string)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write message
    end.to_slice
  end
end
