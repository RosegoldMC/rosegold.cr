require "../../models/chat"

class Rosegold::Clientbound::OpenWindow < Rosegold::Clientbound::Packet
  class_getter packet_id = 0x2E_u8

  property \
    window_id : UInt32,
    window_type : UInt32,
    window_title : Rosegold::Chat

  def initialize(@window_id, @window_type, @window_title)
  end

  def self.read(packet)
    self.new(
      packet.read_var_int,
      packet.read_var_int,
      Rosegold::Chat.from_json(packet.read_var_string),
    )
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write @@packet_id
      buffer.write window_id
      buffer.write window_type
      buffer.write window_title.to_json
    end.to_slice
  end

  def callback(client)
    client.window.close
    client.window = Window.new \
      client, window_id.to_u8, window_title, window_type
    Log.debug { "Server opened window id=#{window_id} type=#{window_type} title: #{window_title}" }
  end
end
