require "../../../minecraft/nbt"
require "../packet"
require "../serverbound/plugin_message"

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
    entity_id = io.read_int
    hardcore = io.read_bool

    dim_count = io.read_var_int
    dimension_names = Array(String).new(dim_count) {
      io.read_var_string
    }

    max_players = io.read_var_int
    view_distance = io.read_var_int
    simulation_distance = io.read_var_int
    reduced_debug_info = io.read_bool
    enable_respawn_screen = io.read_bool
    do_limited_crafting = io.read_bool
    dimension_type = io.read_var_int
    dimension_name = io.read_var_string
    hashed_seed = io.read_long
    gamemode = io.read_byte
    previous_gamemode = io.read_signed_byte
    is_debug = io.read_bool
    is_flat = io.read_bool
    has_death_location = io.read_bool

    death_dimension_name = nil
    death_location = nil
    if has_death_location
      death_dimension_name = io.read_var_string
      death_location = io.read_bit_location
    end

    portal_cooldown = io.read_var_int
    sea_level = io.read_var_int
    enforces_secure_chat = io.read_bool

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

    # Send minecraft:brand plugin message to identify the client
    brand_packet = Rosegold::Serverbound::PluginMessage.brand("Rosegold")
    client.queue_packet(brand_packet)

    Log.debug { "Ingame. #{dimension_name} gamemode=#{gamemode} entity_id=#{entity_id}" }
    Log.debug { "Sent minecraft:brand plugin message with 'Rosegold'" }
  end
end
