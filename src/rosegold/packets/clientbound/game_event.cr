require "../packet"

class Rosegold::Clientbound::GameEvent < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x22_u8, # MC 1.21.8,
  })

  property \
    event : UInt8,
    value : Float32

  def initialize(@event, @value); end

  def self.read(packet)
    event = packet.read_byte
    value = packet.read_float
    self.new(event, value)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write event
      buffer.write value
    end.to_slice
  end

  def callback(client)
    Log.debug { "Game event: #{event} value: #{value}" }
    # Handle specific game events
    case event
    when 0_u8
      Log.debug { "No respawn block available" }
    when 1_u8
      Log.debug { "Begin raining" }
    when 2_u8
      Log.debug { "End raining" }
    when 3_u8
      Log.debug { "Change game mode to #{value.to_i}" }
    when 4_u8
      Log.debug { "Win game - show credits" }
    when 5_u8
      Log.debug { "Demo event - #{value}" }
    when 6_u8
      Log.debug { "Arrow hit player" }
    when 7_u8
      Log.debug { "Rain level change: #{value}" }
    when 8_u8
      Log.debug { "Thunder level change: #{value}" }
    when 9_u8
      Log.debug { "Play pufferfish sting sound" }
    when 10_u8
      Log.debug { "Play elder guardian mob appearance" }
    when 11_u8
      Log.debug { "Enable respawn screen: #{value == 0.0 ? "immediate" : "show screen"}" }
    when 12_u8
      Log.debug { "Limited crafting: #{value == 1.0 ? "enabled" : "disabled"}" }
    when 13_u8
      Log.debug { "Start waiting for level chunks" }
    else
      Log.debug { "Unknown game event: #{event}" }
    end
  end

  # Convenience methods for common game events
  def self.start_waiting_for_chunks
    self.new(13_u8, 0.0_f32)
  end

  def self.change_gamemode(gamemode : Int32)
    self.new(3_u8, gamemode.to_f32)
  end

  def self.enable_respawn_screen(immediate : Bool = false)
    self.new(11_u8, immediate ? 0.0_f32 : 1.0_f32)
  end
end
