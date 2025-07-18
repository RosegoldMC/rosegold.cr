require "../packet"

# `cursor` (in-block coordinates) ranges from 0.0 to 1.0
# and determines e.g. top/bottom slab or left/right door.
class Rosegold::Serverbound::PlayerBlockPlacement < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x2E_u8, # MC 1.18
    767_u32 => 0x2E_u8, # MC 1.21
    771_u32 => 0x2E_u8, # MC 1.21.6
  })

  property \
    hand : Hand,
    location : Vec3i,
    face : BlockFace,
    cursor : Vec3f
  property? inside_block : Bool

  def initialize(
    @hand : Hand,
    @location : Vec3i,
    @face : BlockFace,
    @cursor : Vec3f = Vec3f.new(0.5, 0.5, 0.5),
    @inside_block : Bool = false,
  ); end

  def self.read(io)
    self.new \
      Hand.new(io.read_byte),
      io.read_bit_location,
      BlockFace.new(io.read_byte),
      Vec3f.new(
        io.read_float,
        io.read_float,
        io.read_float),
      io.read_bool
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write hand.value
      buffer.write location
      buffer.write face.value
      buffer.write cursor.x
      buffer.write cursor.y
      buffer.write cursor.z
      buffer.write inside_block?
    end.to_slice
  end
end