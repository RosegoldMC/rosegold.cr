require "../packet"

# Pick the item at the given block position (middle-click on a block).
# The server finds the matching item in the player's inventory,
# moves it to the hotbar, and sends the appropriate slot update packets.
class Rosegold::Serverbound::PickItemFromBlock < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x23_u32, # MC 1.21.8
    774_u32 => 0x23_u32, # MC 1.21.11
    775_u32 => 0x24_u32, # MC 26.1
  })

  property pos : Vec3i
  property? include_data : Bool

  def initialize(@pos : Vec3i, @include_data : Bool = false); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write pos
      buffer.write include_data
    end.to_slice
  end
end
