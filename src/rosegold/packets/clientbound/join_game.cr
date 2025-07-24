require "../../../minecraft/nbt"
require "../packet"

class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x2B_u8, # MC 1.21.8,
  })

  property entity_id : Int32
  property? hardcore : Bool
  property dimension_names : Array(String)
  property max_players : UInt32
  property view_distance : UInt32
  property simulation_distance : UInt32
  property? reduced_debug_info : Bool
  property? enable_respawn_screen : Bool
  property? do_limited_crafting : Bool
  property dimension_type : UInt32
  property dimension_name : String
  property hashed_seed : Int64
  property gamemode : UInt8
  property previous_gamemode : Int8
  property? is_debug : Bool
  property? is_flat : Bool
  property? has_death_location : Bool
  property death_dimension_name : String?
  property death_location : Rosegold::Vec3i?
  property portal_cooldown : UInt32
  property sea_level : UInt32
  property? enforces_secure_chat : Bool

  def initialize(@entity_id, @hardcore, @dimension_names, @max_players, @view_distance, @simulation_distance, @reduced_debug_info, @enable_respawn_screen, @do_limited_crafting, @dimension_type, @dimension_name, @hashed_seed, @gamemode, @previous_gamemode, @is_debug, @is_flat, @has_death_location, @death_dimension_name, @death_location, @portal_cooldown, @sea_level, @enforces_secure_chat); end

  def self.read(io)
    Log.info { "JOINGAME_DEBUG: Starting packet read" }

    Log.info { "JOINGAME_DEBUG: Reading entity_id" }
    entity_id = io.read_int
    Log.info { "JOINGAME_DEBUG: entity_id=#{entity_id}" }

    Log.info { "JOINGAME_DEBUG: Reading hardcore" }
    hardcore = io.read_bool
    Log.info { "JOINGAME_DEBUG: hardcore=#{hardcore}" }

    Log.info { "JOINGAME_DEBUG: Reading dimension_names count" }
    dim_count = io.read_var_int
    Log.info { "JOINGAME_DEBUG: dim_count=#{dim_count}" }
    dimension_names = Array(String).new(dim_count) {
      name = io.read_var_string
      Log.info { "JOINGAME_DEBUG: dimension_name=#{name}" }
      name
    }

    Log.info { "JOINGAME_DEBUG: Reading max_players" }
    max_players = io.read_var_int
    Log.info { "JOINGAME_DEBUG: max_players=#{max_players}" }

    Log.info { "JOINGAME_DEBUG: Reading view_distance" }
    view_distance = io.read_var_int
    Log.info { "JOINGAME_DEBUG: view_distance=#{view_distance}" }

    Log.info { "JOINGAME_DEBUG: Reading simulation_distance" }
    simulation_distance = io.read_var_int
    Log.info { "JOINGAME_DEBUG: simulation_distance=#{simulation_distance}" }

    Log.info { "JOINGAME_DEBUG: Reading reduced_debug_info" }
    reduced_debug_info = io.read_bool
    Log.info { "JOINGAME_DEBUG: reduced_debug_info=#{reduced_debug_info}" }

    Log.info { "JOINGAME_DEBUG: Reading enable_respawn_screen" }
    enable_respawn_screen = io.read_bool
    Log.info { "JOINGAME_DEBUG: enable_respawn_screen=#{enable_respawn_screen}" }

    Log.info { "JOINGAME_DEBUG: Reading do_limited_crafting" }
    do_limited_crafting = io.read_bool
    Log.info { "JOINGAME_DEBUG: do_limited_crafting=#{do_limited_crafting}" }

    Log.info { "JOINGAME_DEBUG: Reading dimension_type" }
    dimension_type = io.read_var_int
    Log.info { "JOINGAME_DEBUG: dimension_type=#{dimension_type}" }

    Log.info { "JOINGAME_DEBUG: Reading dimension_name" }
    dimension_name = io.read_var_string
    Log.info { "JOINGAME_DEBUG: dimension_name=#{dimension_name}" }

    Log.info { "JOINGAME_DEBUG: Reading hashed_seed" }
    hashed_seed = io.read_long
    Log.info { "JOINGAME_DEBUG: hashed_seed=#{hashed_seed}" }

    Log.info { "JOINGAME_DEBUG: Reading gamemode" }
    gamemode = io.read_byte
    Log.info { "JOINGAME_DEBUG: gamemode=#{gamemode}" }

    Log.info { "JOINGAME_DEBUG: Reading previous_gamemode" }
    previous_gamemode = io.read_signed_byte
    Log.info { "JOINGAME_DEBUG: previous_gamemode=#{previous_gamemode}" }

    Log.info { "JOINGAME_DEBUG: Reading is_debug" }
    is_debug = io.read_bool
    Log.info { "JOINGAME_DEBUG: is_debug=#{is_debug}" }

    Log.info { "JOINGAME_DEBUG: Reading is_flat" }
    is_flat = io.read_bool
    Log.info { "JOINGAME_DEBUG: is_flat=#{is_flat}" }

    Log.info { "JOINGAME_DEBUG: Reading has_death_location" }
    has_death_location = io.read_bool
    Log.info { "JOINGAME_DEBUG: has_death_location=#{has_death_location}" }

    death_dimension_name = nil
    death_location = nil
    if has_death_location
      Log.info { "JOINGAME_DEBUG: Reading death_dimension_name" }
      death_dimension_name = io.read_var_string
      Log.info { "JOINGAME_DEBUG: death_dimension_name=#{death_dimension_name}" }

      Log.info { "JOINGAME_DEBUG: Reading death_location" }
      death_location = io.read_bit_location
      Log.info { "JOINGAME_DEBUG: death_location=#{death_location}" }
    end

    Log.info { "JOINGAME_DEBUG: Reading portal_cooldown" }
    portal_cooldown = io.read_var_int
    Log.info { "JOINGAME_DEBUG: portal_cooldown=#{portal_cooldown}" }

    Log.info { "JOINGAME_DEBUG: Reading sea_level" }
    sea_level = io.read_var_int
    Log.info { "JOINGAME_DEBUG: sea_level=#{sea_level}" }

    Log.info { "JOINGAME_DEBUG: Reading enforces_secure_chat" }
    enforces_secure_chat = io.read_bool
    Log.info { "JOINGAME_DEBUG: enforces_secure_chat=#{enforces_secure_chat}" }

    Log.info { "JOINGAME_DEBUG: Creating instance" }

    self.new(
      entity_id,
      hardcore,
      dimension_names,
      max_players,
      view_distance,
      simulation_distance,
      reduced_debug_info,
      enable_respawn_screen,
      do_limited_crafting,
      dimension_type,
      dimension_name,
      hashed_seed,
      gamemode,
      previous_gamemode,
      is_debug,
      is_flat,
      has_death_location,
      death_dimension_name,
      death_location,
      portal_cooldown,
      sea_level,
      enforces_secure_chat
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write hardcore?
      buffer.write dimension_names.size
      dimension_names.each { |name| buffer.write name }
      buffer.write max_players
      buffer.write view_distance
      buffer.write simulation_distance
      buffer.write reduced_debug_info?
      buffer.write enable_respawn_screen?
      buffer.write do_limited_crafting?
      buffer.write dimension_type
      buffer.write dimension_name
      buffer.write_full hashed_seed
      buffer.write gamemode
      buffer.write previous_gamemode
      buffer.write is_debug?
      buffer.write is_flat?
      buffer.write has_death_location?
      if has_death_location?
        buffer.write death_dimension_name.not_nil!
        buffer.write death_location.not_nil!
      end
      buffer.write portal_cooldown
      buffer.write sea_level
      buffer.write enforces_secure_chat?
    end.to_slice
  end

  def callback(client)
    client.player.entity_id = entity_id.to_u64
    client.player.gamemode = gamemode.to_i8
    # Note: dimension is no longer NBT data, just the dimension type ID
    # This may need adjustment based on how Dimension class is implemented
    # client.dimension = Dimension.new dimension_name, dimension_type

    Log.debug { "Ingame. #{dimension_name} gamemode=#{gamemode} entity_id=#{entity_id}" }
  end
end
