require "../packet"

class Rosegold::Serverbound::HeldItemChange < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x34_u8, # MC 1.21.8,
  })

  property hotbar_nr : Int16

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : Int16)
    clamp_hotbar_selection
  end

  def initialize(hotbar_nr : UInt32)
    @hotbar_nr = hotbar_nr.to_i16
    clamp_hotbar_selection
  end

  def clamp_hotbar_selection
    @hotbar_nr = 0_i16 if @hotbar_nr < 0_i16 || @hotbar_nr > 8_i16
  end

  def self.read(packet)
    self.new(packet.read_short)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full hotbar_nr.to_u16
    end.to_slice
  end
end
