require "../packet"

class Rosegold::Clientbound::FinishConfiguration < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for FinishConfiguration
  packet_ids({
    767_u32 => 0x03_u8, # MC 1.21
    771_u32 => 0x03_u8, # MC 1.21.6
  })

  class_getter state = ProtocolState::CONFIGURATION

  def initialize; end

  def self.read(packet)
    self.new
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
    end.to_slice
  end

  def callback(client)
    # When we receive FinishConfiguration from server, we need to acknowledge it
    # by sending our own FinishConfiguration packet, then transition to PLAY state
    client.send_packet! Rosegold::Serverbound::FinishConfiguration.new
    client.set_protocol_state(ProtocolState::PLAY)
    Log.info { "Configuration finished, transitioning to PLAY state" }
  end
end
