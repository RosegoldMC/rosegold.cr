require "json"
require "../packet"

class Rosegold::Clientbound::StatusResponse < Rosegold::Clientbound::Packet
  class_getter packet_id = 0_u8

  property json_response : JSON::Any

  def initialize(@json_response); end

  def self.read(packet)
    new JSON.parse packet.read_var_string
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write json_response.to_s
    end.to_slice
  end
end

Rosegold::ProtocolState::STATUS.register Rosegold::Clientbound::StatusResponse
