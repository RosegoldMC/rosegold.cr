require "../packet"

class Rosegold::Serverbound::LoginStart < Rosegold::Serverbound::Packet
  class_getter packet_id = 0x00_u8
  class_getter state = Rosegold::ProtocolState::LOGIN

  property username : String
  property player_uuid : UUID?

  def initialize(@username : String, @player_uuid : UUID? = nil); end

  def self.read(packet)
    username = packet.read_var_string
    # For protocol 767+, also read UUID
    if Client.protocol_version >= 767
      player_uuid = packet.read_uuid
      self.new username, player_uuid
    else
      self.new username
    end
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write username
      
      # For protocol 767+ (MC 1.21), also include UUID
      if Client.protocol_version >= 767
        # Use provided UUID or generate a default one
        uuid = player_uuid || UUID.new("00000000-0000-0000-0000-000000000000")
        buffer.write uuid
      end
    end.to_slice
  end
end
