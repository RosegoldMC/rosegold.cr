require "../packet"

# Ticking State packet (0x78)
# Used to adjust the ticking rate of the client, and whether it's frozen.
class Rosegold::Clientbound::TickingState < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    769_u32 => 0x78_u8, # MC 1.21.4,
    771_u32 => 0x78_u8, # MC 1.21.6,
  })

  property \
    tick_rate : Float32,
    is_frozen : Bool

  def initialize(@tick_rate, @is_frozen)
  end

  def self.read(packet)
    tick_rate = packet.read_float
    is_frozen = packet.read_bool
    self.new(tick_rate, is_frozen)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |io|
      io.write self.class.packet_id_for_protocol(Client.protocol_version)
      io.write tick_rate
      io.write is_frozen
    end.to_slice
  end

  def callback(client)
    Log.debug { "Received ticking state: rate=#{tick_rate}, frozen=#{is_frozen}" }
    client.update_ticking_state(tick_rate, is_frozen)
  end
end