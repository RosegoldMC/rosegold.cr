require "../packet"

# Ticking Step packet (0x79) 
# Advances the client processing by the specified number of ticks.
# Has no effect unless client ticking is frozen.
class Rosegold::Clientbound::TickingStep < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    769_u32 => 0x79_u8, # MC 1.21.4,
    771_u32 => 0x79_u8, # MC 1.21.6,
    772_u32 => 0x79_u8, # MC 1.21.8,
  })

  property \
    tick_steps : UInt32

  def initialize(@tick_steps)
  end

  def self.read(packet)
    tick_steps = packet.read_var_int
    self.new(tick_steps)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write tick_steps
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received ticking step: advancing #{tick_steps} ticks" }
    client.add_tick_steps(tick_steps)
  end
end
