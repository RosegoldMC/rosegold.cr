require "../packet"

# MC 26.1+: set game rules
class Rosegold::Serverbound::SetGameRule < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    775_u32 => 0x39_u32, # MC 26.1
  })

  property rules : Array({String, String})

  def initialize(@rules = Array({String, String}).new); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write rules.size
      rules.each do |key, value|
        buffer.write key
        buffer.write value
      end
    end.to_slice
  end
end
