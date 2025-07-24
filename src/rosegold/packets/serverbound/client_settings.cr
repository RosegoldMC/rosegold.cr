require "../packet"

class Rosegold::Serverbound::ClientSettings < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x0D_u8, # MC 1.21.8,
  })

  enum ChatMode
    Enabled; CommandsOnly; Hidden
  end

  enum Hand
    Left; Right
  end

  @[Flags]
  enum SkinParts
    Cape; Jacket; LeftSleeve; RightSleeve; LeftLeg; RightLeg; Hat
  end

  # TODO: Add new properties for 1.19+
  property locale : String = "en_US"
  property view_distance : UInt8 = 1 # Chunks. Only needed for physics
  property chat_mode : ChatMode = :enabled
  property? chat_colors : Bool = true
  property skin_parts : SkinParts = SkinParts::All
  property main_hand : Hand = :right
  property? text_filtering : Bool = false
  property? allow_server_listings : Bool = true

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write locale
      buffer.write view_distance
      buffer.write chat_mode.value
      buffer.write chat_colors?
      buffer.write skin_parts.value.to_u8
      buffer.write main_hand.value
      buffer.write text_filtering?
      buffer.write allow_server_listings?
    end.to_slice
  end
end
