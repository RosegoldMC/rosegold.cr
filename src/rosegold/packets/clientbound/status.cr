require "json"

class Rosegold::Clientbound::Status < Rosegold::Clientbound::Packet
  property \
    json_response : JSON::Any

  def initialize(@json_response)
  end

  def self.read(packet)
    new JSON.parse packet.read_var_string
  end
end
