require "../packet"

class Rosegold::Serverbound::LoginAcknowledged < Rosegold::Serverbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs
  # LoginAcknowledged is only required for protocol 767+ (MC 1.21+)
  packet_ids({
    772_u32 => 0x03_u8, # MC 1.21.8,
  })

  class_getter state = Rosegold::ProtocolState::LOGIN

  def initialize; end

  def self.read(packet)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      # Use protocol-aware packet ID
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end

  def callback(client)
    # After sending LoginAcknowledged, we're now in CONFIGURATION state
    # Send ClientInformation packet to configure the client
    client.send_packet! Rosegold::Serverbound::ClientInformation.new
    Log.debug { "Sent ClientInformation during configuration phase" }
  end
end
