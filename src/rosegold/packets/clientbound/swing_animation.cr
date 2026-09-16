require "../../inventory/slot"
require "../packet"

class Rosegold::Clientbound::SwingAnimation < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    777_u32 => 0x7B_u32,
  })

  property entity_id : Int32, hand : Hand, animation : DataComponents::SwingAnimation

  def initialize(@entity_id, @hand, @animation); end

  def self.read(packet)
    new(
      packet.read_var_int.to_i32,
      Hand.new(packet.read_var_int.to_i32),
      DataComponents::SwingAnimation.read(packet),
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write entity_id
      buffer.write hand.value
      animation.write(buffer)
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received swing animation packet for entity ID #{entity_id}" }
  end
end
