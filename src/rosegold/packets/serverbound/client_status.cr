require "../packet"

class Rosegold::Serverbound::ClientStatus < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x04_u8

  enum Action
    Respawn; RequestStats
  end

  property action : Action

  def initialize(@action : Action = :respawn); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write action.value
    end.to_slice
  end
end
