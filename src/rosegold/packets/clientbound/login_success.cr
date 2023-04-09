require "../packet"

class Rosegold::Clientbound::LoginSuccess < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x02_u8
  class_getter state = ProtocolState::LOGIN

  property \
    uuid : UUID,
    username : String

  def initialize(@uuid, @username); end

  def self.read(packet)
    self.new(
      packet.read_uuid,
      packet.read_var_string
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write uuid
      buffer.write username
    end.to_slice
  end

  def callback(client)
    client.state = ProtocolState::PLAY.clientbound
    Log.info { "Logged in as #{username} #{uuid}" }
    client.player.uuid = uuid
    client.player.username = username
  end
end
