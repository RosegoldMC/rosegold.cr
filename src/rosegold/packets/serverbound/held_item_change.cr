require "../packet"

class Rosegold::Serverbound::HeldItemChange < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x25_u8, # MC 1.18
    767_u32 => 0x2F_u8, # MC 1.21
    771_u32 => 0x2F_u8, # MC 1.21.6
  })

  property hotbar_nr : UInt8

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt8)
    if @hotbar_nr > 8
      Log.warn { "Invalid hotbar selection #{@hotbar_nr}, clamping to 0" }
      @hotbar_nr = 0_u8
    end
  end

  def self.read(packet)
    self.new(packet.read_short.to_u8)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full hotbar_nr.to_u16
    end.to_slice
  end
end
