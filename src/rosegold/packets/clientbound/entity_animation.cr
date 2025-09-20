require "../packet"

class Rosegold::Clientbound::EntityAnimation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x02_u8, # MC 1.21.8
  })
  class_getter state = ProtocolState::PLAY

  enum Animation : UInt8
    SwingMainArm     = 0
    LeaveBed         = 2
    SwingOffHand     = 3
    CriticalHit      = 4
    MagicCriticalHit = 5
  end

  property \
    entity_id : Int32,
    animation : Animation

  def initialize(@entity_id, @animation)
  end

  def self.read(packet)
    entity_id = packet.read_var_int.to_i32
    animation_byte = packet.read_byte.to_u8
    animation = Animation.from_value?(animation_byte) || Animation.new(animation_byte)

    self.new(entity_id, animation)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)

      buffer.write entity_id
      buffer.write animation.value
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received entity animation packet for entity ID #{entity_id}, animation #{animation}" }
  end
end
