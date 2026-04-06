require "../packet"

class Rosegold::Clientbound::LoginPluginRequest < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x04_u32, # MC 1.21.8
    774_u32 => 0x04_u32, # MC 1.21.11
    775_u32 => 0x04_u32, # MC 26.1
  })
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
      Bytes.new(packet.size - packet.pos).tap { |buf| packet.read_fully(buf) }
    )
  end

  def callback(client)
    client.queue_packet Serverbound::LoginPluginResponse.new(
      self.message_id
    )
  end
end
