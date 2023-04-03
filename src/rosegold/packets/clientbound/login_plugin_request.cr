require "../packet"

class Rosegold::Clientbound::LoginPluginRequest < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x04_u8
  class_getter state = Rosegold::ProtocolState::LOGIN

  property \
    message_id : UInt32,
    channel_identifier : String,
    data : Bytes

  def initialize(@message_id, @channel_identifier, @data); end

  def self.read(packet)
    self.new(
      packet.read_var_int,
      packet.read_var_string,
      packet.read_var_bytes
    )
  end

  def callback(client)
    client.queue_packet Serverbound::LoginPluginResponse.new(
      self.message_id
    )
  end
end
