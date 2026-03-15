require "../packet"

# Jump boost is from 0 to 100
class Rosegold::Serverbound::EntityAction < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x29_u32, # MC 1.21.8 (Player Command)
    774_u32 => 0x29_u32, # MC 1.21.11
  })

  property \
    entity_id : UInt64,
    action : Symbol,
    jump_boost : UInt8

  def initialize(@entity_id, @action, @jump_boost = 0); end

  private def action_value : Int32
    case action
    when :leave_bed            then 0
    when :start_sprinting      then 1
    when :stop_sprinting       then 2
    when :start_horse_jump     then 3
    when :stop_horse_jump      then 4
    when :open_horse_inventory then 5
    when :start_elytra_flying  then 6
    else                            raise "Unknown action: #{action}"
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id.to_u32
      buffer.write action_value.to_u32
      buffer.write jump_boost
    end.to_slice
  end
end
