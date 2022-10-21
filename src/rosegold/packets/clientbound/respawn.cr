class Rosegold::Clientbound::Respawn < Rosegold::Clientbound::Packet
  property \
    dimension : NBT::Tag,
    dimension_name : String,
    hashed_seed : Int64,
    gamemode : Int8,
    prev_gamemode : Int8,
    is_debug : Bool,
    is_flat : Bool,
    copy_metadata : Bool

  def initialize(@dimension, @dimension_name, @hashed_seed, @gamemode, @prev_gamemode, @is_debug, @is_flat, @copy_metadata); end

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

  def callback(client)
    min_y = dimension["min_y"].as_i
    world_height = dimension["height"].as_i

    client.dimension = World::Dimension.new min_y, world_height

    Log.debug { "Respawned in #{dimension_name} gamemode=#{gamemode}" }
  end
end
