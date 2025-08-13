require "../packet"

# `cursor` (in-block coordinates) ranges from 0.0 to 1.0
# and determines e.g. top/bottom slab or left/right door.
class Rosegold::Serverbound::PlayerBlockPlacement < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x3F_u8, # MC 1.21.8,
  })

  property \
    hand : Hand,
    location : Vec3i,
    face : BlockFace,
    cursor : Vec3f,
    sequence : Int32
  property? inside_block : Bool

  def initialize(
    @hand : Hand,
    @location : Vec3i,
    @face : BlockFace,
    @cursor : Vec3f = Vec3f.new(0.5, 0.5, 0.5),
    @inside_block : Bool = false,
    @sequence : Int32 = 0,
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

      # MC 1.21+ adds sequence number
      if Client.protocol_version >= 767_u32
        buffer.write false # TODO: world border hit, probably false
        buffer.write sequence
      end
    end.to_slice
  end
end
