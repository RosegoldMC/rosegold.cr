require "../packet"

class Rosegold::Clientbound::CloseWindow < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    772_u32 => 0x11_u8, # MC 1.21.8,
  })

  property \
    window_id : UInt32

  def initialize(@window_id)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int,
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
    end.to_slice
  end

  def callback(client)
    if client.container_menu && window_id == client.container_menu.id
      Log.debug { "Server closed container #{client.container_menu}" }
      client.container_menu.handle_close
    elsif window_id == 0
      Log.debug { "Server requested close of player inventory (ignored)" }
    else
      container_id = client.container_menu.try(&.id) || "nil"
      Log.warn { "Server closed unknown window: #{window_id}. Current container: #{container_id}. Ignoring." }
      Log.debug { self }
    end
  end
end
