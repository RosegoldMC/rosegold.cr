require "../packet"

class Rosegold::Clientbound::Transfer < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  # Define protocol-specific packet IDs for Transfer (configuration)
  packet_ids({
    772_u32 => 0x0B_u8, # MC 1.21.8,
  })

  class_getter state = ProtocolState::CONFIGURATION

  property host : String
  property port : UInt32

  def initialize(@host : String, @port : UInt32); end

  def self.read(packet)
    host = packet.read_var_string
    port = packet.read_var_int
    self.new(host, port)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write host
      buffer.write port
    end.to_slice
  end

  def callback(client)
    Log.info { "Received transfer request to #{host}:#{port}" }

    begin
      client.transfer_to(host, port)
      Log.info { "Server transfer to #{host}:#{port} completed successfully" }
    rescue e
      Log.error { "Server transfer to #{host}:#{port} failed: #{e.message}" }
      raise e
    end
  end
end
