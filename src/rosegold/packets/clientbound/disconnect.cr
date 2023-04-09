require "../packet"

class Rosegold::Clientbound::Disconnect < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x1a_u8

  property reason : Chat

  def initialize(@reason); end

  def self.read(packet)
    self.new Chat.from_json(packet.read_var_string)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write reason.to_json
    end.to_slice
  end

  def callback(client)
    client.connection.disconnect reason
  end
end
