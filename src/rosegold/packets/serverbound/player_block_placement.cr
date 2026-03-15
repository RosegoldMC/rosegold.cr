require "../packet"

# `cursor` (in-block coordinates) ranges from 0.0 to 1.0
# and determines e.g. top/bottom slab or left/right door.
class Rosegold::Serverbound::PlayerBlockPlacement < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x3F_u32, # MC 1.21.8
    774_u32 => 0x3F_u32, # MC 1.21.11
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
    hand = Hand.new(io.read_var_int.to_i32)
    location = io.read_bit_location
    face = BlockFace.new(io.read_var_int.to_i32)
    cursor = Vec3f.new(io.read_float, io.read_float, io.read_float)
    inside_block = io.read_bool
    io.read_bool # world_border_hit
    sequence = io.read_var_int.to_i32
    self.new(hand, location, face, cursor, inside_block, sequence)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write hand.value.to_u32
      buffer.write location
      buffer.write face.value.to_u32
      buffer.write cursor.x
      buffer.write cursor.y
      buffer.write cursor.z
      buffer.write inside_block?
      buffer.write false # world_border_hit
      buffer.write sequence.to_u32
    end.to_slice
  end
end
