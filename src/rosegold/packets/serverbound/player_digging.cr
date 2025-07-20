require "../packet"

class Rosegold::Serverbound::PlayerDigging < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x1A_u8, # MC 1.18
    767_u32 => 0x24_u8, # MC 1.21
    771_u32 => 0x24_u8, # MC 1.21.6
  })

  enum Status
    Start; Cancel; Finish; DropHandFull; DropHandSingle; FinishUsingHand; SwapHands
  end

  property \
    status : Status,
    location : Vec3i,
    face : BlockFace,
    sequence : Int32

  def initialize(
    @status : Status,
    @location : Vec3i = Vec3i::ORIGIN,
    @face : BlockFace = :bottom,
    @sequence : Int32 = 0,
  ); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write status.value
      buffer.write location
      buffer.write face.value

      # MC 1.21+ adds sequence number
      if Client.protocol_version >= 767_u32
        buffer.write sequence
      end
    end.to_slice
  end
end
