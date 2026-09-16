require "../../world/vec3"
require "../packet"

class Rosegold::Clientbound::AddTransientBlock < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::PLAY
  packet_ids({777_u32 => 0x25_u32})

  property location : Vec3i
  property block_state : UInt32

  def initialize(@location, @block_state); end

  def self.read(packet)
    new(packet.read_bit_location, packet.read_var_int)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write location
      buffer.write block_state
    end.to_slice
  end
end
