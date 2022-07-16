class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  property \
    entity_id : Int32,
    hardcore : Bool

  def initialize(@entity_id, @hardcore)
  end

  def self.read(packet)
    self.new(
      packet.read_int,
      packet.read_bool
    )
  end

  def callback(client)
    client.state = State::Play.new
  end
end
