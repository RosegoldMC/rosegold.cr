require "../packet"
require "../../world/vec3"

class Rosegold::Clientbound::Respawn < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x4B_u8, # MC 1.21.8,
  })

  property \
    dimension_type : UInt32,
    dimension_name : String,
    hashed_seed : Int64,
    gamemode : UInt8,
    previous_gamemode : Int8
  property? \
    is_debug : Bool,
    is_flat : Bool,
    has_death_location : Bool
  property \
    death_dimension_name : String?,
    death_location : Vec3i?,
    portal_cooldown : UInt32,
    sea_level : UInt32,
    data_kept : UInt8

  def initialize(@dimension_type, @dimension_name, @hashed_seed, @gamemode, @previous_gamemode, @is_debug, @is_flat, @has_death_location, @death_dimension_name, @death_location, @portal_cooldown, @sea_level, @data_kept); end

  def self.read(packet)
    dimension_type = packet.read_var_int
    dimension_name = packet.read_var_string
    hashed_seed = packet.read_long
    gamemode = packet.read_byte
    previous_gamemode = packet.read_signed_byte
    is_debug = packet.read_bool
    is_flat = packet.read_bool
    has_death_location = packet.read_bool

    death_dimension_name = has_death_location ? packet.read_var_string : nil
    death_location = has_death_location ? packet.read_bit_location : nil

    portal_cooldown = packet.read_var_int
    sea_level = packet.read_var_int
    data_kept = packet.read_byte

    self.new(
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
      data_kept
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write dimension_type
      buffer.write dimension_name
      buffer.write_full hashed_seed
      buffer.write gamemode
      buffer.write previous_gamemode
      buffer.write is_debug?
      buffer.write is_flat?
      buffer.write has_death_location?

      if has_death_location?
        if death_dim_name = death_dimension_name
          buffer.write death_dim_name
        end
        if death_loc = death_location
          buffer.write death_loc
        end
      end

      buffer.write portal_cooldown
      buffer.write sea_level
      buffer.write data_kept
    end.to_slice
  end

  def callback(client)
    client.physics.pause
    client.player.gamemode = gamemode.to_i8

    # Update dimension based on dimension_name
    # TODO: set dimension based on dimension_type via registry
    client.dimension = Dimension.for_dimension_name(dimension_name)

    Log.debug { "Respawned in #{dimension_name} gamemode=#{gamemode} dimension_type=#{dimension_type}" }
  end
end
