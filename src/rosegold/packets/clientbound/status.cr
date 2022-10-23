require "json"
require "../packet"

class Rosegold::Clientbound::Status < Rosegold::Clientbound::Packet
  class_getter packet_id = 0_u8

  property json_response : JSON::Any

  def initialize(@json_response); end

  def self.read(packet)
    new JSON.parse packet.read_var_string
  end
end

Rosegold::ProtocolState::STATUS.register Rosegold::Clientbound::Status
