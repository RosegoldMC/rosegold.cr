require "../../models/chat"

class Rosegold::Clientbound::OpenWindow < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  # Define protocol-specific packet IDs
  packet_ids({
    758_u32 => 0x2E_u8, # MC 1.18
    767_u32 => 0x33_u8, # MC 1.21
    769_u32 => 0x33_u8, # MC 1.21.4,
    771_u32 => 0x33_u8, # MC 1.21.6,
  })

  property \
    window_id : UInt32,
    window_type : UInt32,
    window_title : Rosegold::Chat

  def initialize(@window_id, @window_type, @window_title)
  end

  def self.read(packet)
    window_id = packet.read_var_int
    window_type = packet.read_var_int

    # Handle window title parsing with better error handling
    title_string = ""
    begin
      title_string = packet.read_var_string
      window_title = if title_string.empty?
                       Rosegold::Chat.new("Window")
                     else
                       Rosegold::Chat.from_json(title_string)
                     end
    rescue JSON::ParseException
      # JSON parsing failed, treat as plain text
      Log.warn { "Failed to parse window title as JSON: '#{title_string}', treating as plain text" }
      window_title = Rosegold::Chat.new(title_string.empty? ? "Window" : title_string)
    rescue
      # Any other error, use default
      Log.warn { "Error reading window title, using default" }
      window_title = Rosegold::Chat.new("Window")
    end

    self.new(window_id, window_type, window_title)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write window_id
      buffer.write window_type
      buffer.write window_title.to_json
    end.to_slice
  end

  def callback(client)
    # Clamp window_id to valid UInt8 range
    clamped_id = window_id > 255 ? 255_u8 : window_id.to_u8
    client.window = Window.new \
      client, clamped_id, window_title, window_type
    Log.debug { "Server opened window id=#{window_id} type=#{window_type} title: #{window_title}" }
  end
end
