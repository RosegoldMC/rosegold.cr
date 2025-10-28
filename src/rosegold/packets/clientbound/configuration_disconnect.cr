require "../packet"
require "../../models/text_component"

class Rosegold::Clientbound::ConfigurationDisconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x02_u8, # MC 1.21.8
  })
  class_getter state = ProtocolState::CONFIGURATION

  property reason : TextComponent

  def initialize(@reason); end

  def initialize(reason_string : String)
    @reason = TextComponent.new(reason_string)
  end

  def self.read(packet)
    # MC 1.21+ uses NBT text component format

    reason_nbt = packet.read_nbt_unamed
    text_component = nbt_to_text_component(reason_nbt)
    self.new text_component
  rescue
    # Fallback if NBT reading fails
    Log.warn { "Failed to parse configuration disconnect reason as NBT, trying as string" }
    reason_string = packet.read_var_string rescue "Unknown disconnect reason"
    self.new TextComponent.new(reason_string)
  end

  private def self.nbt_to_text_component(nbt : Minecraft::NBT::Tag) : TextComponent
    TextComponent.from_nbt(nbt)
  rescue
    # Fallback for any NBT parsing errors
    TextComponent.new("Configuration disconnect reason (parsing error)")
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
