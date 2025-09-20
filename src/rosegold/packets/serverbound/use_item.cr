require "../packet"

class Rosegold::Serverbound::UseItem < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x40_u8, # MC 1.21.8,
  })

  property hand : Hand, sequence : Int32, yaw : Float32, pitch : Float32

  def initialize(@hand : Hand = Hand::MainHand, @sequence : Int32 = 0, @yaw : Float32 = 0.0_f32, @pitch : Float32 = 0.0_f32); end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write hand.value

      # MC 1.21+ adds sequence number, yaw, and pitch
      buffer.write sequence
      buffer.write yaw
      buffer.write pitch
    end.to_slice
  end
end
