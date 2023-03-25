require "../../../minecraft/nbt"

class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  property \
    entity_id : Int32,
    gamemode : UInt8,
    previous_gamemode : UInt8,
    world_count : UInt32,
    dimension_names : Array(String),
    dimension_codec : Minecraft::NBT::Tag,
    dimension : Minecraft::NBT::Tag,
    dimension_name : String,
    hashed_seed : Int64,
    max_players : UInt32,
    view_distance : UInt32,
    simulation_distance : UInt32,
    gamemode : UInt8
  property? \
    hardcore : Bool,
    is_debug : Bool,
    is_flat : Bool,
    reduced_debug_info : Bool,
    enable_respawn_screen : Bool

  def initialize(
    @entity_id, @hardcore, @gamemode, @previous_gamemode, @world_count, @dimension_names,
    @dimension_codec, @dimension, @dimension_name, @hashed_seed, @max_players, @view_distance,
    @simulation_distance, @reduced_debug_info, @enable_respawn_screen, @is_debug, @is_flat
  )
  end

  def self.read(packet)
    self.new(
      packet.read_int,
      packet.read_bool,
      packet.read_byte,
      packet.read_byte,
      world_count = packet.read_var_int,
      Array(String).new(world_count) { packet.read_var_string },
      packet.read_nbt,
      packet.read_nbt,
      packet.read_var_string,
      packet.read_long,
      packet.read_var_int,
      packet.read_var_int,
      packet.read_var_int,
      packet.read_bool,
      packet.read_bool,
      packet.read_bool,
      packet.read_bool
    )
  end

  def callback(client)
    Log.debug { "Ingame. gamemode=#{gamemode} entity_id=#{entity_id}" }

    client.dimension.min_y = dimension.as(Minecraft::NBT::CompoundTag)["min_y"].as(Minecraft::NBT::IntTag).value
    client.dimension.height = dimension.as(Minecraft::NBT::CompoundTag)["height"].as(Minecraft::NBT::IntTag).value
  end
end
