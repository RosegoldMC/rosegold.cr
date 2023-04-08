require "../packet"

class Rosegold::Clientbound::Respawn < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x3d_u8

  property \
    dimension : Minecraft::NBT::Tag,
    dimension_name : String,
    hashed_seed : Int64,
    gamemode : Int8,
    previous_gamemode : Int8
  property? \
    is_debug : Bool,
    is_flat : Bool,
    copy_metadata : Bool

  def initialize(@dimension, @dimension_name, @hashed_seed, @gamemode, @previous_gamemode, @is_debug, @is_flat, @copy_metadata); end

  def self.read(packet)
    self.new(
      packet.read_nbt,
      packet.read_var_string,
      packet.read_long,
      packet.read_signed_byte,
      packet.read_signed_byte,
      packet.read_bool,
      packet.read_bool,
      packet.read_bool
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write dimension
      buffer.write dimension_name
      buffer.write_full hashed_seed
      buffer.write gamemode
      buffer.write previous_gamemode
      buffer.write is_debug?
      buffer.write is_flat?
      buffer.write copy_metadata?
    end.to_slice
  end

  def callback(client)
    client.physics.pause
    client.player.gamemode = gamemode
    client.dimension = Dimension.new dimension_name, dimension

    Log.debug { "Respawned in #{dimension_name} gamemode=#{gamemode}" }
  end
end
