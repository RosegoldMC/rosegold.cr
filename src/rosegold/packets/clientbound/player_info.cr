require "../../world/player_list"
require "../packet"

class Rosegold::Clientbound::PlayerInfo < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x36_u8

  enum Action
    Add; Gamemode; Ping; DisplayName; Remove
  end

  property action : Action
  property players : Array(PlayerList::Entry)

  def initialize(@action, @players = Array(PlayerList::Entry).new); end

  def self.read(io)
    action = Action.new(io.read_var_int.to_i32)
    players = Array(PlayerList::Entry).new(io.read_var_int) do
      PlayerList::Entry.new(io.read_uuid).tap do |player|
        case action
        when .add?
          player.name = io.read_var_string
          player.properties = Array(PlayerList::Property).new(io.read_var_int) do
            PlayerList::Property.new(
              io.read_var_string,
              io.read_var_string,
              io.read_opt_string)
          end
          player.gamemode = io.read_var_int
          player.ping = io.read_var_int
          if io.read_bool
            player.display_name = Rosegold::Chat.from_json io.read_var_string
          end
        when .gamemode?
          player.gamemode = io.read_var_int
        when .ping?
          player.ping = io.read_var_int
        when .display_name?
          if io.read_bool
            player.display_name = Rosegold::Chat.from_json io.read_var_string
          end
        when .remove?
          # only uuid field (already read)
        else raise "Invalid PlayerInfo action #{action}"
        end
      end
    end
    self.new(action, players)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write action.value
      buffer.write players.size
      players.each do |player|
        buffer.write player.uuid
        case action
        when .add?
          buffer.write player.name.not_nil!
          buffer.write player.properties.size
          player.properties.each do |prop|
            buffer.write prop.name
            buffer.write prop.value
            buffer.write_opt_string prop.signature
          end
          buffer.write player.gamemode.not_nil!
          buffer.write player.ping.not_nil!
          buffer.write_opt_string player.display_name.try &.to_json
        when .gamemode?
          buffer.write player.gamemode.not_nil!
        when .ping?
          buffer.write player.ping.not_nil!
        when .display_name?
          buffer.write_opt_string player.display_name.try &.to_json
        when .remove?
          # only uuid field (already written)
        else raise "Invalid PlayerInfo action #{action}"
        end
      end
    end.to_slice
  end

  def callback(client)
    players.each do |player|
      case action
      when .add?
        client.online_players[player.uuid] = player
      when .remove?
        client.online_players.delete player.uuid
      else
        client.online_players[player.uuid]?.try &.update player
      end
    end
  end
end

Rosegold::ProtocolState::PLAY.register Rosegold::Clientbound::PlayerInfo
