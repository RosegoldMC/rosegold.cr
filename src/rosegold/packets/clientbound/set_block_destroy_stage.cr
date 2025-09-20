require "../../world/vec3"

class Rosegold::Clientbound::SetBlockDestroyStage < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x05_u8, # MC 1.21.8
  })
  class_getter state = ProtocolState::PLAY

  property \
    entity_id : Int32,
    location : Vec3i,
    destroy_stage : UInt8

  def initialize(@entity_id, @location, @destroy_stage)
  end

  def self.read(packet)
    entity_id = packet.read_var_int
    location = packet.read_bit_location
    destroy_stage = packet.read_byte.to_u8

    self.new(entity_id.to_i32, location, destroy_stage)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      buffer.write entity_id
      buffer.write location
      buffer.write destroy_stage
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received set block destroy stage packet for entity ID #{entity_id}, location #{location}, stage #{destroy_stage}" }
    # The client handles block destruction visualization locally
  end
end
