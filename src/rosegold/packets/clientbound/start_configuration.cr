require "../packet"

class Rosegold::Clientbound::StartConfiguration < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x6F_u8, # MC 1.21.8,
  })

  class_getter state = ProtocolState::PLAY

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
    client.send_packet! Rosegold::Serverbound::AcknowledgeConfiguration.new
    Log.info { "Sent AcknowledgeConfiguration packet" }

    # Pause physics to prevent falling during transfer
    client.physics.pause
    Log.info { "Paused physics during configuration transition" }

    client.set_protocol_state(ProtocolState::CONFIGURATION)
    Log.info { "Start configuration received, transitioning to CONFIGURATION state" }
  end
end
