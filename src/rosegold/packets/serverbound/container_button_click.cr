require "../packet"

class Rosegold::Serverbound::ContainerButtonClick < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x10_u32,
    773_u32 => 0x10_u32,
    774_u32 => 0x10_u32,
    775_u32 => 0x11_u32,
    776_u32 => 0x11_u32,
    777_u32 => 0x11_u32,
  })

  property container_id : UInt32
  property button_id : Int32

  def initialize(@container_id, @button_id)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write container_id
      buffer.write button_id
    end.to_slice
  end
end
