require "../packet"
require "../../models/text_component"

class Rosegold::Clientbound::ConfigurationDisconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x02_u32, # MC 1.21.8
    774_u32 => 0x02_u32, # MC 1.21.11
    775_u32 => 0x02_u32, # MC 26.1
  })
  class_getter state = ProtocolState::CONFIGURATION

  property reason : TextComponent

  def initialize(@reason); end

  def initialize(reason_string : String)
    @reason = TextComponent.new(reason_string)
  end

  def self.read(packet)
    self.new TextComponent.from_nbt(packet.read_nbt_unamed)
  rescue
    Log.warn { "Failed to parse configuration disconnect reason" }
    self.new TextComponent.new("Unknown disconnect reason")
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # MC 1.21+ uses NBT text component format
      reason.write(buffer)
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason.to_s
  end
end
