require "./packet"

class Rosegold::Clientbound::HeldItemChange < Rosegold::Clientbound::Packet
  PACKET_ID = 0x48_u8

  property hotbar_nr : UInt8

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt8); end

  def self.read(packet)
    self.new(packet.read_byte)
  end

  def callback(client)
    client.player.hotbar_selection = hotbar_nr
  end
end
