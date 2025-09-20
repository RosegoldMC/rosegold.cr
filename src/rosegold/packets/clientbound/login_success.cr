require "../packet"

class Rosegold::Clientbound::LoginSuccess < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Property class for LoginSuccess properties (similar to PlayerList::Property)
  class Property
    getter name : String, value : String, signature : String?

    def initialize(@name, @value, @signature = nil); end
  end

  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x02_u8, # MC 1.21.8,
  })

  class_getter state = ProtocolState::LOGIN

  property \
    uuid : UUID,
    username : String,
    properties : Array(Property)

  def initialize(@uuid, @username, @properties = [] of Property); end

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

    self.new(uuid, username, properties)
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
