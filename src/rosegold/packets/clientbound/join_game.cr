class Rosegold::Clientbound::JoinGame < Rosegold::Clientbound::Packet
  property \
    entity_id : Int32,
    hardcore : Bool,
    gamemode : UInt8

  def initialize(@entity_id, @hardcore, @gamemode)
  end

  def self.read(packet)
    self.new(
      packet.read_int32,
      packet.read_bool,
      packet.read_byte
    )
  end

  def callback(client)
    client.log_debug { "Ingame. gamemode=#{gamemode} entity_id=#{entity_id}" }
  end
end
