require "../packet"

# Jump boost is from 0 to 100
class Rosegold::Serverbound::EntityAction < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x1b_u8, # MC 1.18
    767_u32 => 0x29_u8, # MC 1.21 (Player Command)
    771_u32 => 0x29_u8, # MC 1.21.6 (Player Command)
  })

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
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write action.value
      buffer.write jump_boost
    end.to_slice
  end
end
