require "../packet"

module Rosegold::Clientbound::PostEffectsCodec
  def self.read_post_effects(packet)
    Array(String).new(packet.read_var_int) { packet.read_var_string }
  end

  def self.write_post_effects(packet_id : UInt32, post_effects : Array(String)) : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write packet_id
      buffer.write post_effects.size
      post_effects.each { |post_effect| buffer.write post_effect }
    end.to_slice
  end
end

class Rosegold::Clientbound::ConfigurationPostEffects < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({777_u32 => 0x0A_u32})

  property post_effects : Array(String)

  def initialize(@post_effects = [] of String); end

  def self.read(packet)
    new(PostEffectsCodec.read_post_effects(packet))
  end

  def write : Bytes
    PostEffectsCodec.write_post_effects(self.class.packet_id_for_protocol(Client.protocol_version), post_effects)
  end

  def callback(client)
    client.post_effects = post_effects.dup
  end
end

class Rosegold::Clientbound::PostEffects < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::PLAY
  packet_ids({777_u32 => 0x53_u32})

  property post_effects : Array(String)

  def initialize(@post_effects = [] of String); end

  def self.read(packet)
    new(PostEffectsCodec.read_post_effects(packet))
  end

  def write : Bytes
    PostEffectsCodec.write_post_effects(self.class.packet_id_for_protocol(Client.protocol_version), post_effects)
  end

  def callback(client)
    client.post_effects = post_effects.dup
  end
end
