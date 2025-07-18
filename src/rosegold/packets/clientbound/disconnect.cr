require "../packet"

class Rosegold::Clientbound::Disconnect < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x1a_u8, # MC 1.18
    767_u32 => 0x1a_u8, # MC 1.21
    771_u32 => 0x1a_u8, # MC 1.21.6
  })

  property reason : Chat

  def initialize(@reason); end

  def self.read(packet)
    self.new Chat.from_json(packet.read_var_string)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write reason.to_json
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason
  end
end