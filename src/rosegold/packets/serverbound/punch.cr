require "../packet"

# MC 26.3+: the server owns attack and block-breaking swing animation.
class Rosegold::Serverbound::Punch < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    777_u32 => 0x2E_u32,
  })

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end
end
