require "socket"
require "../events/*"
require "../packets/*"
require "../world/*"
require "../../minecraft/nbt"
require "../../minecraft/io"

# Forward declaration to avoid circular dependency
class Rosegold::Client; end

class Rosegold::Spectate::Server
  DEFAULT_SPECTATOR_ENTITY_ID = 0x7fffffff
  DEFAULT_RENDER_DISTANCE     =          4
  DEFAULT_VIEW_DISTANCE       =     10_u32
  DEFAULT_SIMULATION_DISTANCE =      3_u32
  KEEP_ALIVE_INTERVAL         = 20.seconds
  INVENTORY_POLL_INTERVAL     = 1.second
  BOT_MONITOR_INTERVAL        = 50.milliseconds
  MAX_CONNECTIONS             = 10

  UNIMPLEMENTED_FORWARDED = {
    "set_entity_motion"            => {772_u32 => 0x5E_u32, 774_u32 => 0x63_u32},
    "set_entity_data"              => {772_u32 => 0x5C_u32, 774_u32 => 0x61_u32},
    "sound"                        => {772_u32 => 0x6E_u32, 774_u32 => 0x73_u32},
    "update_attributes"            => {772_u32 => 0x7C_u32, 774_u32 => 0x81_u32},
    "world_particles"              => {772_u32 => 0x29_u32, 774_u32 => 0x2E_u32},
    "explosion"                    => {772_u32 => 0x20_u32, 774_u32 => 0x24_u32},
    "scoreboard_objective"         => {772_u32 => 0x63_u32, 774_u32 => 0x68_u32},
    "scoreboard_score"             => {772_u32 => 0x67_u32, 774_u32 => 0x6C_u32},
    "scoreboard_display_objective" => {772_u32 => 0x5B_u32, 774_u32 => 0x60_u32},
    "reset_score"                  => {772_u32 => 0x48_u32, 774_u32 => 0x4D_u32},
    "teams"                        => {772_u32 => 0x66_u32, 774_u32 => 0x6B_u32},
    "set_title_text"               => {772_u32 => 0x6B_u32, 774_u32 => 0x70_u32},
    "set_title_subtitle"           => {772_u32 => 0x69_u32, 774_u32 => 0x6E_u32},
    "set_title_time"               => {772_u32 => 0x6C_u32, 774_u32 => 0x71_u32},
    "clear_titles"                 => {772_u32 => 0x0E_u32, 774_u32 => 0x0E_u32},
    "action_bar"                   => {772_u32 => 0x50_u32, 774_u32 => 0x55_u32},
    "playerlist_header"            => {772_u32 => 0x73_u32, 774_u32 => 0x78_u32},
    "hurt_animation"               => {772_u32 => 0x24_u32, 774_u32 => 0x29_u32},
    "damage_event"                 => {772_u32 => 0x19_u32, 774_u32 => 0x19_u32},
    "entity_sound_effect"          => {772_u32 => 0x6D_u32, 774_u32 => 0x72_u32},
    "entity_head_rotation"         => {772_u32 => 0x4C_u32, 774_u32 => 0x51_u32},
    "entity_status"                => {772_u32 => 0x1E_u32, 774_u32 => 0x22_u32},
    "initialize_world_border"      => {772_u32 => 0x25_u32, 774_u32 => 0x2A_u32},
    "world_border_center"          => {772_u32 => 0x51_u32, 774_u32 => 0x56_u32},
    "world_border_lerp_size"       => {772_u32 => 0x52_u32, 774_u32 => 0x57_u32},
    "world_border_size"            => {772_u32 => 0x53_u32, 774_u32 => 0x58_u32},
    "world_border_warning_delay"   => {772_u32 => 0x54_u32, 774_u32 => 0x59_u32},
    "world_border_warning_reach"   => {772_u32 => 0x55_u32, 774_u32 => 0x5A_u32},
    "world_event"                  => {772_u32 => 0x28_u32, 774_u32 => 0x2D_u32},
    "block_action"                 => {772_u32 => 0x07_u32, 774_u32 => 0x07_u32},
    "tile_entity_data"             => {772_u32 => 0x06_u32, 774_u32 => 0x06_u32},
    "experience"                   => {772_u32 => 0x60_u32, 774_u32 => 0x65_u32},
    "set_cooldown"                 => {772_u32 => 0x16_u32, 774_u32 => 0x16_u32},
    "collect"                      => {772_u32 => 0x75_u32, 774_u32 => 0x7A_u32},
    "attach_entity"                => {772_u32 => 0x5D_u32, 774_u32 => 0x62_u32},
    "entity_teleport"              => {772_u32 => 0x76_u32, 774_u32 => 0x7B_u32},
  }

  macro build_forwarded_packets_method
    def self.forwarded_packets(protocol : UInt32) : Hash(UInt32, String)
      result = Hash(UInt32, String).new

      {% for klass in [
                        Clientbound::SystemChatMessage,
                        Clientbound::CloseWindow,
                        Clientbound::OpenWindow,
                        Clientbound::BlockChange,
                        Clientbound::MultiBlockChange,
                        Clientbound::SpawnEntity,
                        Clientbound::EntityPositionSync,
                        Clientbound::EntityPosition,
                        Clientbound::EntityRotation,
                        Clientbound::EntityPositionAndRotation,
                        Clientbound::EntityEquipment,
                        Clientbound::DestroyEntities,
                        Clientbound::PlayerInfoUpdate,
                        Clientbound::PlayerInfoRemove,
                        Clientbound::SetBlockDestroyStage,
                        Clientbound::UpdateHealth,
                        Clientbound::EntityEffect,
                        Clientbound::RemoveEntityEffect,
                        Clientbound::SetTime,
                        Clientbound::EntityAnimation,
                        Clientbound::GameEvent,
                        Clientbound::SetPassengers,
                      ] %}
        result[{{klass}}[protocol]] = {{klass.name.split("::").last}}
      {% end %}

      UNIMPLEMENTED_FORWARDED.each do |name, ids|
        if id = ids[protocol]?
          result[id] = name
        end
      end

      result
    end
  end

  build_forwarded_packets_method

  Log = ::Log.for self

  property host : String
  property port : Int32
  property client : Rosegold::Client?
  property server : TCPServer?
  property connections = Array(Connection).new

  def initialize(@host : String = "127.0.0.1", @port : Int32 = 25566)
  end

  def start
    @server = TCPServer.new(host, port)
    Log.info { "SpectateServer listening on #{host}:#{port}" }

    spawn do
      while server = @server
        begin
          client_socket = server.accept

          if @connections.size >= MAX_CONNECTIONS
            Log.warn { "Max connections reached, rejecting #{client_socket.remote_address}" }
            client_socket.close
            next
          end

          Log.info { "New spectator connection from #{client_socket.remote_address}" }

          connection = Connection.new(client_socket, self)
          @connections << connection

          spawn do
            connection.handle_client
          rescue e
            Log.error { "Spectator connection error: #{e}" }
          ensure
            connection.close
            @connections.delete(connection)
          end
        rescue e : IO::Error
          Log.debug { "Server accept error: #{e}" }
          break if server.closed?
        end
      end
    end
  end

  def stop
    @server.try &.close
    @connections.dup.each(&.close)
    @connections.clear
  end

  def attach_client(client : Rosegold::Client)
    @client = client
  end

  def detach_client
    @client = nil
  end
end
