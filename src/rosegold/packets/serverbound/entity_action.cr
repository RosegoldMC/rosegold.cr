require "./packet"

# sneak/sprint/leave bed
class Rosegold::Serverbound::EntityAction < Rosegold::Serverbound::Packet
  PACKET_ID = 0x1b_u32

  property \
    entity_id : UInt32,
    action_id : UInt8,
    jump_boost : UInt8

  def initialize(
    @entity_id : UInt32,
    @action_id : UInt8,
    @jump_boost : UInt8
  ); end

  def to_packet : Minecraft::IO
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write PACKET_ID
      buffer.write entity_id
      buffer.write action_id
      buffer.write jump_boost
    end
  end
end
