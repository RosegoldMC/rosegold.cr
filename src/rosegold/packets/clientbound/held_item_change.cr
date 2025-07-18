require "../packet"

class Rosegold::Clientbound::HeldItemChange < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x48_u8, # MC 1.18
    767_u32 => 0x48_u8, # MC 1.21
    771_u32 => 0x48_u8, # MC 1.21.6
  })

  property hotbar_nr : UInt8

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt8); end

  def self.read(packet)
    self.new(packet.read_byte)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write hotbar_nr
    end.to_slice
  end

  def callback(client)
    client.player.hotbar_selection = hotbar_nr
  end
end