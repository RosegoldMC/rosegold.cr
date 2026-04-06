require "../packet"

class Rosegold::Clientbound::SetCamera < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x56_u32, # MC 1.21.8
    774_u32 => 0x5B_u32, # MC 1.21.11
    775_u32 => 0x5D_u32, # MC 26.1
  })
  class_getter state = ProtocolState::PLAY

  property entity_id : UInt32

  def initialize(entity_id : UInt32)
    @entity_id = entity_id
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_u32
    self.new(entity_id)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_i32
    end.to_slice
  end

  def callback(client)
    Log.debug { "Set camera to entity ID #{entity_id}" }
  end
end
