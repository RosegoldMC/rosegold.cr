require "../packet"

class Rosegold::Serverbound::LoginStart < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x00_u8, # MC 1.18
    767_u32 => 0x00_u8, # MC 1.21
    769_u32 => 0x00_u8, # MC 1.21.4,
    771_u32 => 0x00_u8, # MC 1.21.6,
    772_u32 => 0x00_u8, # MC 1.21.8,
  })

  class_getter state = Rosegold::ProtocolState::LOGIN

  property username : String
  property player_uuid : UUID?
  property protocol_version : UInt32

  def initialize(@username : String, @player_uuid : UUID? = nil, @protocol_version : UInt32 = Client.protocol_version); end

  def self.read(packet)
    username = packet.read_var_string
    # For protocol 767+, also read UUID
    if Client.protocol_version >= 767
      player_uuid = packet.read_uuid
      self.new username, player_uuid, Client.protocol_version
    else
      self.new username, nil, Client.protocol_version
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(protocol_version)
      buffer.write username

      # For protocol 767+ (MC 1.21), also include UUID
      if protocol_version >= 767
        # Use provided UUID or generate a default one
        uuid = player_uuid || UUID.new("00000000-0000-0000-0000-000000000000")
        buffer.write uuid
      end
    end.to_slice
  end
end
