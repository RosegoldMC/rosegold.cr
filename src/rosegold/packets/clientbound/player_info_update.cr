require "../packet"

class Rosegold::Clientbound::PlayerInfoUpdate < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x3F_u8, # MC 1.21.8,
  })

  # Action flags (bitfield)
  ADD_PLAYER          = 0x01_u8
  INITIALIZE_CHAT     = 0x02_u8
  UPDATE_GAMEMODE     = 0x04_u8
  UPDATE_LISTED       = 0x08_u8
  UPDATE_LATENCY      = 0x10_u8
  UPDATE_DISPLAY_NAME = 0x20_u8

  property \
    actions : UInt8,
    players : Array(PlayerEntry)

  def initialize(@actions, @players); end

  struct PlayerEntry
    property uuid : UUID
    property name : String?
    property properties : Array(Property)?
    property gamemode : Int32?
    property listed : Bool?
    property latency : Int32?
    property display_name : Rosegold::TextComponent?

    def initialize(@uuid, @name = nil, @properties = nil, @gamemode = nil, @listed = nil, @latency = nil, @display_name = nil)
    end

    struct Property
      property name : String
      property value : String
      property signature : String?

      def initialize(@name, @value, @signature = nil)
      end
    end
  end

  def self.read(packet)
    actions = packet.read_byte
    player_count = packet.read_var_int

    players = Array(PlayerEntry).new(player_count.to_i32) do
      uuid = packet.read_uuid

      # Read fields based on action flags
      name = nil
      properties = nil
      if (actions & ADD_PLAYER) != 0
        name = packet.read_var_string
        prop_count = packet.read_var_int
        properties = Array(PlayerEntry::Property).new(prop_count.to_i32) do
          prop_name = packet.read_var_string
          prop_value = packet.read_var_string
          prop_signature = packet.read_bool ? packet.read_var_string : nil
          PlayerEntry::Property.new(prop_name, prop_value, prop_signature)
        end
      end

      # Skip other fields for now - implement as needed
      gamemode = (actions & UPDATE_GAMEMODE) != 0 ? packet.read_var_int.to_i32 : nil
      listed = (actions & UPDATE_LISTED) != 0 ? packet.read_bool : nil
      latency = (actions & UPDATE_LATENCY) != 0 ? packet.read_var_int.to_i32 : nil
      display_name = (actions & UPDATE_DISPLAY_NAME) != 0 ? (packet.read_bool ? Rosegold::TextComponent.read(packet) : nil) : nil

      PlayerEntry.new(uuid, name, properties, gamemode, listed, latency, display_name)
    end

    self.new(actions, players)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write actions
      buffer.write players.size

      players.each do |player|
        buffer.write player.uuid

        # Write fields based on action flags
        if (actions & ADD_PLAYER) != 0
          buffer.write player.name.not_nil! # ameba:disable Lint/NotNil
          if props = player.properties
            buffer.write props.size
            props.each do |prop|
              buffer.write prop.name
              buffer.write prop.value
              if sig = prop.signature
                buffer.write true
                buffer.write sig
              else
                buffer.write false
              end
            end
          else
            buffer.write 0_u32 # No properties
          end
        end

        if (actions & UPDATE_GAMEMODE) != 0
          buffer.write player.gamemode.not_nil! # ameba:disable Lint/NotNil
        end

        if (actions & UPDATE_LISTED) != 0
          buffer.write player.listed.not_nil! # ameba:disable Lint/NotNil
        end

        if (actions & UPDATE_LATENCY) != 0
          buffer.write player.latency.not_nil! # ameba:disable Lint/NotNil
        end

        if (actions & UPDATE_DISPLAY_NAME) != 0
          if display_name = player.display_name
            buffer.write true
            buffer.write display_name
          else
            buffer.write false
          end
        end
      end
    end.to_slice
  end

  def callback(client)
    Log.debug { "Player info update: actions=0x#{actions.to_s(16).upcase.rjust(2, '0')}, #{players.size} players" }
    players.each do |player|
      # Get or create player list entry
      entry = client.player_list[player.uuid]? || Rosegold::PlayerList::Entry.new(player.uuid)

      # Update fields based on action flags
      if (actions & ADD_PLAYER) != 0
        entry.name = player.name
        if props = player.properties
          entry.properties = props.map do |prop|
            Rosegold::PlayerList::Property.new(prop.name, prop.value, prop.signature)
          end
        end
        Log.debug { "  Added player: #{player.name} (#{player.uuid})" }
      end

      if (actions & UPDATE_GAMEMODE) != 0
        entry.gamemode = player.gamemode.try(&.to_i8)
      end

      if (actions & UPDATE_LATENCY) != 0
        entry.ping = player.latency.try(&.to_u32)
      end

      if (actions & UPDATE_DISPLAY_NAME) != 0
        entry.display_name = player.display_name
      end

      # Store/update the entry in player list
      client.player_list[player.uuid] = entry
    end
  end

  # Convenience method to create an "Add Player" packet
  def self.add_player(uuid : UUID, name : String, gamemode : Int32 = 0, latency : Int32 = 0, properties : Array(PlayerEntry::Property)? = nil)
    actions = ADD_PLAYER | UPDATE_GAMEMODE | UPDATE_LISTED | UPDATE_LATENCY
    player = PlayerEntry.new(
      uuid: uuid,
      name: name,
      properties: properties || [] of PlayerEntry::Property,
      gamemode: gamemode,
      listed: true,
      latency: latency
    )
    self.new(actions, [player])
  end

  # Convenience method to remove a player
  def self.remove_player(uuid : UUID)
    # This actually requires PlayerInfoRemove packet (0x3E), not this packet
    # But we can create an update packet that sets listed = false
    actions = UPDATE_LISTED
    player = PlayerEntry.new(uuid: uuid, listed: false)
    self.new(actions, [player])
  end
end
