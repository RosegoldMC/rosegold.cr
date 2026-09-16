require "../packet"

class Rosegold::Clientbound::LoginSuccess < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Property class for LoginSuccess properties (similar to PlayerList::Property)
  class Property
    getter name : String, value : String, signature : String?

    def initialize(@name, @value, @signature = nil); end
  end

  packet_ids({
    772_u32 => 0x02_u32, # MC 1.21.8
    774_u32 => 0x02_u32, # MC 1.21.11
    773_u32 => 0x02_u32, # MC 1.21.9
    775_u32 => 0x02_u32, # MC 26.1
    776_u32 => 0x02_u32, # MC 26.2
    777_u32 => 0x02_u32, # MC 26.3
  })

  class_getter state = ProtocolState::LOGIN

  property \
    uuid : UUID,
    username : String,
    properties : Array(Property),
    session_id : UUID

  def initialize(@uuid, @username, @properties = [] of Property, @session_id = UUID.new("00000000-0000-0000-0000-000000000000")); end

  def self.read(packet)
    uuid = packet.read_uuid
    username = packet.read_var_string

    # For protocol 767+ (MC 1.21+), also read properties array
    properties = Array(Property).new(packet.read_var_int) do
      Property.new(
        packet.read_var_string,                         # name
        packet.read_var_string,                         # value
        packet.read_bool ? packet.read_var_string : nil # signature (optional)
      )
    end

    session_id = Client.protocol_version >= 776_u32 ? packet.read_uuid : UUID.new("00000000-0000-0000-0000-000000000000")

    self.new(uuid, username, properties, session_id)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write uuid
      buffer.write username

      # For protocol 767+ (MC 1.21+), also write properties array
      buffer.write properties.size
      properties.each do |prop|
        buffer.write prop.name
        buffer.write prop.value
        if signature = prop.signature
          buffer.write true
          buffer.write signature
        else
          buffer.write false
        end
      end

      buffer.write session_id if Client.protocol_version >= 776_u32
    end.to_slice
  end

  def callback(client)
    # For protocol 767+ (MC 1.21+), send LoginAcknowledged packet and transition to CONFIGURATION state
    client.send_packet! Rosegold::Serverbound::LoginAcknowledged.new
    client.set_protocol_state(ProtocolState::CONFIGURATION)

    Log.info { "Logged in as #{username} #{uuid}" }
    client.player.uuid = uuid
    client.player.username = username
  end
end
