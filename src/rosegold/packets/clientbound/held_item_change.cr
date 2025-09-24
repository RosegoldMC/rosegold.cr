require "../packet"

class Rosegold::Clientbound::HeldItemChange < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x62_u8, # MC 1.21.8,
  })

  property hotbar_nr : UInt32

  # `hotbar_nr` ranges from 0 to 8
  def initialize(@hotbar_nr : UInt32)
    raise ArgumentError.new("Hotbar number must be between 0 and 8") unless (0..8).includes?(@hotbar_nr)
  end

  def self.read(packet)
    self.new(packet.read_var_int)
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
