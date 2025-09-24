require "../packet"
require "../../models/text_component"

class Rosegold::Clientbound::LoginDisconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x00_u8, # MC 1.21.8,
  })
  class_getter state = Rosegold::ProtocolState::LOGIN

  property reason : TextComponent

  def initialize(@reason); end

  def initialize(reason_string : String)
    @reason = TextComponent.new(reason_string)
  end

  def self.read(packet)
    reason_json = packet.read_var_string
    begin
      self.new TextComponent.from_json(reason_json)
    rescue JSON::ParseException
      Log.warn { "Failed to parse login disconnect reason as JSON: #{reason_json.inspect}" }
      self.new TextComponent.new(reason_json)
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write reason.to_json
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason.to_s
  end
end
