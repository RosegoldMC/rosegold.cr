require "../packet"

class Rosegold::Clientbound::CloseWindow < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x13_u8, # MC 1.18
    767_u32 => 0x0F_u8, # MC 1.21
    769_u32 => 0x0F_u8, # MC 1.21.4,
    771_u32 => 0x0F_u8, # MC 1.21.6,
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
    if window_id == client.window.id
      Log.debug { "Server closed window #{client.window}" }
      client.window.handle_closed
    else
      Log.warn { "Server closed the wrong window: #{window_id}. Ignoring." }
      Log.debug { self }
    end
  end
end
