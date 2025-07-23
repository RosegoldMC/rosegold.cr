require "../../world/player_list"
require "../packet"

class Rosegold::Clientbound::PlayerInfo < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x36_u8, # MC 1.18
    767_u32 => 0x36_u8, # MC 1.21
    769_u32 => 0x36_u8, # MC 1.21.4,
    771_u32 => 0x36_u8, # MC 1.21.6,
    772_u32 => 0x3F_u8, # MC 1.21.8,
  })

  # 1.21.8 uses action masks instead of enum
  @[Flags]
  enum ActionMask : UInt8
    AddPlayer          = 0x01
    InitializeChat     = 0x02
    UpdateGameMode     = 0x04
    UpdateListed       = 0x08
    UpdateLatency      = 0x10
    UpdateDisplayName  = 0x20
    UpdateListPriority = 0x40
    UpdateHat          = 0x80
  end

  property actions : ActionMask
  property players : Array(PlayerList::Entry)

  def initialize(@actions, @players = Array(PlayerList::Entry).new); end

  def self.read(io)
    # Read EnumSet - fixed size for 8 actions: ceil(8/8) = 1 byte
    actions = ActionMask.new(io.read_byte)
    players = Array(PlayerList::Entry).new(io.read_var_int) do
      uuid = io.read_uuid
      PlayerList::Entry.new(uuid).tap do |player|
        # Read actions in the order they appear based on the mask
        active_actions = [] of ActionMask
        ActionMask.each do |mask|
          active_actions << mask if actions.includes?(mask)
        end

        active_actions.each do |action_type|
          case action_type
          when .add_player?
            player.name = io.read_var_string
            player.properties = Array(PlayerList::Property).new(io.read_var_int) do
              PlayerList::Property.new(
                io.read_var_string,
                io.read_var_string,
                io.read_opt_string)
            end
          when .initialize_chat?
            # Skip chat session data for now
            if io.read_bool     # has signature data
              io.read_uuid      # chat session id
              io.read_long      # public key expiry time
              io.read_var_bytes # encoded public key
              io.read_var_bytes # public key signature
            end
          when .update_game_mode?
            player.gamemode = io.read_var_int.to_i8
          when .update_listed?
            # Skip listed flag for now
            io.read_bool
          when .update_latency?
            player.ping = io.read_var_int
          when .update_display_name?
            if io.read_bool
              player.display_name = Rosegold::Chat.from_json io.read_var_string
            end
          when .update_list_priority?
            # Skip priority for now
            io.read_var_int
          when .update_hat?
            # Skip hat visibility for now
            io.read_bool
          end
        end
      end
    end
    self.new(actions, players)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      # Write EnumSet - fixed 1 byte for 8 action types
      buffer.write actions.value
      buffer.write players.size
      players.each do |player|
        buffer.write player.uuid

        # Write actions in the same order as read
        active_actions = [] of ActionMask
        ActionMask.each do |mask|
          active_actions << mask if actions.includes?(mask)
        end

        active_actions.each do |action_type|
          case action_type
          when .add_player?
            buffer.write player.name.not_nil!
            buffer.write player.properties.size
            player.properties.each do |prop|
              buffer.write prop.name
              buffer.write prop.value
              buffer.write_opt_string prop.signature
            end
          when .initialize_chat?
            # Write empty chat session data
            buffer.write false # has signature data
          when .update_game_mode?
            buffer.write player.gamemode.not_nil!
          when .update_listed?
            buffer.write true # default to listed
          when .update_latency?
            buffer.write player.ping.not_nil!
          when .update_display_name?
            buffer.write_opt_string player.display_name.try &.to_json
          when .update_list_priority?
            buffer.write 0 # default priority
          when .update_hat?
            buffer.write true # default hat visible
          end
        end
      end
    end.to_slice
  end

  def callback(client)
    players.each do |player|
      if actions.includes?(ActionMask::AddPlayer)
        client.online_players[player.uuid] = player
      else
        # Update existing player
        client.online_players[player.uuid]?.try &.update player
      end

      if player.gamemode && player.uuid == client.player.uuid
        client.player.gamemode = player.gamemode.not_nil!
      end
    end
  end
end
