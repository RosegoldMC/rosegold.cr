require "../../models/text_component"
require "../packet"

class Rosegold::Clientbound::CommandSuggestionsResponse < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping

  packet_ids({
    772_u32 => 0x0F_u32,
    774_u32 => 0x0F_u32,
    775_u32 => 0x0F_u32,
  })

  record Match, text : String, tooltip : Rosegold::TextComponent? = nil

  property transaction_id : UInt32
  property start : UInt32
  property length : UInt32
  property matches : Array(Match)

  def initialize(@transaction_id, @start, @length, @matches); end

  def self.read(io)
    transaction_id = io.read_var_int
    start = io.read_var_int
    length = io.read_var_int
    count = io.read_var_int
    matches = Array(Match).new(count)
    count.times do
      text = io.read_var_string
      tooltip = io.read_bool ? io.read_text_component : nil
      matches << Match.new(text, tooltip)
    end
    self.new(transaction_id, start, length, matches)
  end

  def write : Bytes
    Minecraft::IO::Memory.new.tap do |buffer|
      buffer.write self.class.packet_id_for_protocol(Client.protocol_version)
      buffer.write transaction_id
      buffer.write start
      buffer.write length
      buffer.write matches.size.to_u32
      matches.each do |match|
        buffer.write match.text
        if tooltip = match.tooltip
          buffer.write true
          tooltip.write(buffer)
        else
          buffer.write false
        end
      end
    end.to_slice
  end
end
