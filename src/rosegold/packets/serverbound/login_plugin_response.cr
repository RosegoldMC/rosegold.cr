require "../packet"

class Rosegold::Serverbound::LoginPluginResponse < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x02_u8
  class_getter state = Rosegold::ProtocolState::LOGIN

  property message_id : UInt32

  def initialize(@message_id); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write message_id
      buffer.write false
    end.to_slice
  end
end
