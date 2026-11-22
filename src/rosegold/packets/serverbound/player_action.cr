require "../packet"

class Rosegold::Serverbound::PlayerAction < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x28_u32, # MC 1.21.8
    774_u32 => 0x28_u32, # MC 1.21.11
    773_u32 => 0x28_u32, # MC 1.21.9
    775_u32 => 0x29_u32, # MC 26.1
    776_u32 => 0x29_u32, # MC 26.2
    777_u32 => 0x29_u32,
  })

  enum Status
    Start; Cancel; Finish; DropHandFull; DropHandSingle; FinishUsingHand; SwapHands; ChangeDestroyDirection
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
      wire_status = if status.change_destroy_direction?
                      raise ArgumentError.new("ChangeDestroyDirection requires protocol 777 or later") if Client.protocol_version < 777_u32
                      1
                    elsif Client.protocol_version >= 777_u32 && !status.start?
                      status.value + 1
                    else
                      status.value
                    end
      buffer.write wire_status
      buffer.write location
      buffer.write face.value

      # MC 1.21+ adds sequence number
      buffer.write sequence
    end.to_slice
  end
end
