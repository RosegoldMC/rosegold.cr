class Rosegold::Clientbound::LoginSuccess < Rosegold::Clientbound::Packet
  property \
    uuid : UUID,
    username : String

  def initialize(@uuid, @username)
  end

  def self.read(packet)
    self.new(
      packet.read_uuid,
      packet.read_var_string
    )
  end

  def callback(client)
    client.state = State::Play.new
    client.log_info { "Logged in as #{username} #{uuid}" }
  end
end
