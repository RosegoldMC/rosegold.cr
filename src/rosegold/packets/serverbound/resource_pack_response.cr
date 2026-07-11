require "../packet"

class Rosegold::Serverbound::ResourcePackResponse < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  class_getter state = ProtocolState::CONFIGURATION
  packet_ids({
    772_u32 => 0x06_u32, # MC 1.21.8
    773_u32 => 0x06_u32, # MC 1.21.9
    774_u32 => 0x06_u32, # MC 1.21.11
    775_u32 => 0x06_u32, # MC 26.1
    776_u32 => 0x06_u32, # MC 26.2
  })

  enum Action
    SuccessfullyLoaded = 0
    Declined           = 1
    FailedDownload     = 2
    Accepted           = 3
    Downloaded         = 4
    InvalidURL         = 5
    FailedReload       = 6
    Discarded          = 7
  end

  property \
    id : UUID,
    action : Action

  def initialize(@id, @action); end

  def self.read(packet)
    id = packet.read_uuid
    action = Action.new(packet.read_var_int.to_i32)

    self.new(id, action)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write id
      buffer.write action.value
    end.to_slice
  end
end
