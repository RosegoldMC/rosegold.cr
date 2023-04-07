require "../packet"

# Respawn: action=0
class Rosegold::Serverbound::ClientSettings < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x04_u8

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
      buffer.write @@packet_id
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
