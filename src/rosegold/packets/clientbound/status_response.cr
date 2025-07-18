require "json"
require "../packet"

class Rosegold::Clientbound::StatusResponse < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs (same across all versions)
  packet_ids({
    758_u32 => 0x00_u8, # MC 1.18
    767_u32 => 0x00_u8, # MC 1.21
    771_u32 => 0x00_u8, # MC 1.21.6
  })

  class_getter state = Rosegold::ProtocolState::STATUS

  property json_response : JSON::Any

  def initialize(@json_response); end

  def self.read(packet)
    new JSON.parse packet.read_var_string
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write json_response.to_json
    end.to_slice
  end
end
