require "../../../minecraft/nbt"
require "../packet"

class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x26_u8, # MC 1.18
    767_u32 => 0x29_u8, # MC 1.21
    771_u32 => 0x29_u8, # MC 1.21.6
  })

  property entity_id : UInt64
  property? hardcore : Bool
  property gamemode : Int8
  property previous_gamemode : Int8
  property dimension_names : Array(String)
  property dimension_codec : Minecraft::NBT::Tag
  property dimension : Minecraft::NBT::Tag
  property dimension_name : String
  property hashed_seed : Int64
  property max_players : UInt32
  property view_distance : UInt32
  property simulation_distance : UInt32
  property? reduced_debug_info : Bool
  property? enable_respawn_screen : Bool
  property? is_debug : Bool
  property? is_flat : Bool

  def initialize(@entity_id, @hardcore, @gamemode, @previous_gamemode, @dimension_names, @dimension_codec, @dimension, @dimension_name, @hashed_seed, @max_players, @view_distance, @simulation_distance, @reduced_debug_info, @enable_respawn_screen, @is_debug, @is_flat); end

  def self.read(io)
    self.new(
      io.read_int.to_u64,
      io.read_bool,
      io.read_signed_byte,
      io.read_signed_byte,
      Array(String).new(io.read_var_int) { io.read_var_string },
      io.read_nbt,
      io.read_nbt,
      io.read_var_string,
      io.read_long,
      io.read_var_int,
      io.read_var_int,
      io.read_var_int,
      io.read_bool,
      io.read_bool,
      io.read_bool,
      io.read_bool
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write_full entity_id
      buffer.write hardcore?
      buffer.write gamemode
      buffer.write previous_gamemode
      buffer.write dimension_names.size
      dimension_names.each { |name| buffer.write name }
      buffer.write dimension_codec
      buffer.write dimension
      buffer.write dimension_name
      buffer.write_full hashed_seed
      buffer.write max_players
      buffer.write view_distance
      buffer.write simulation_distance
      buffer.write reduced_debug_info?
      buffer.write enable_respawn_screen?
      buffer.write is_debug?
      buffer.write is_flat?
    end.to_slice
  end

  def callback(client)
    client.player.entity_id = entity_id
    client.player.gamemode = gamemode
    client.dimension = Dimension.new dimension_name, dimension

    Log.debug { "Ingame. #{dimension_name} gamemode=#{gamemode} entity_id=#{entity_id}" }
  end
end
