require "../packet"

# sneak/sprint/leave bed
class Rosegold::Serverbound::EntityAction < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x1b_u8

  property \
    entity_id : UInt32,
    action_id : UInt8,
    jump_boost : UInt8

  def initialize(
    @entity_id : UInt32,
    @action_id : UInt8,
    @jump_boost : UInt8
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write action_id
      buffer.write jump_boost
    end.to_slice
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Serverbound::EntityAction
