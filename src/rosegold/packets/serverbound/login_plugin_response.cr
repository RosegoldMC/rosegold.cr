class Rosegold::Serverbound::LoginPluginResponse < Rosegold::Serverbound::Packet
  PACKET_ID = 0x02_u8

  property \
    message_id : UInt32

  def initialize(
    @message_id
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write message_id
      buffer.write false
    end
  end
end
