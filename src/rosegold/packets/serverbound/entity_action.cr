require "../packet"

# Jump boost is from 0 to 100
class Rosegold::Serverbound::EntityAction < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x1b_u8

  enum Type
    StartSneaking; StopSneaking
    LeaveBed
    StartSprinting; StopSprinting
    StartHorseJump; StopHorseJump
    OpenHorseInventory
    StartElytraFlying
  end

  property \
    entity_id : UInt64,
    action : Type,
    jump_boost : UInt8

  def initialize(@entity_id, @action, @jump_boost = 0); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write entity_id
      buffer.write action.value
      buffer.write jump_boost
    end.to_slice
  end
end
