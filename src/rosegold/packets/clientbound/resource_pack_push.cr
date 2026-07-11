require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::ResourcePackPush < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    772_u32 => 0x09_u32, # MC 1.21.8
    773_u32 => 0x09_u32, # MC 1.21.9
    774_u32 => 0x09_u32, # MC 1.21.11
    775_u32 => 0x09_u32, # MC 26.1
    776_u32 => 0x09_u32, # MC 26.2
  })

  property \
    id : UUID,
    url : String,
    hash : String,
    prompt : TextComponent?

  property? forced : Bool

  def initialize(@id, @url, @hash, @forced, @prompt = nil); end

  def self.read(packet)
    id = packet.read_uuid
    url = packet.read_var_string
    hash = packet.read_var_string
    forced = packet.read_bool
    prompt = packet.read_bool ? packet.read_text_component : nil

    self.new(id, url, hash, forced, prompt)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write id
      buffer.write url
      buffer.write hash
      buffer.write forced?
      if prompt = self.prompt
        buffer.write true
        prompt.write(buffer)
      else
        buffer.write false
      end
    end.to_slice
  end

  def callback(client)
    actions = self.class.response_actions(client.resource_pack_response)
    actions.each { |action| client.send_packet! Serverbound::ResourcePackResponse.new(id, action) }
  end

  def self.response_actions(policy : Symbol) : Array(Serverbound::ResourcePackResponse::Action)
    case policy
    when :decline
      [Serverbound::ResourcePackResponse::Action::Declined]
    else
      [Serverbound::ResourcePackResponse::Action::Accepted, Serverbound::ResourcePackResponse::Action::SuccessfullyLoaded]
    end
  end
end
