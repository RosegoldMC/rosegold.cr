require "../packet"
require "../../inventory/recipe"

class Rosegold::Clientbound::RecipeBookAdd < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    772_u32 => 0x43_u32, # MC 1.21.8
    774_u32 => 0x48_u32, # MC 1.21.11
  })

  FLAG_SHOW_NOTIFICATION = 0x01_u8
  FLAG_HIGHLIGHT         = 0x02_u8

  property recipe_entries : Array(RecipeDisplayEntry)
  property flags_map : Hash(UInt32, UInt8)
  property? replace : Bool
  property parse_error : String?
  property expected_count : UInt32 = 0_u32

  def initialize(@recipe_entries, @flags_map, @replace); end

  def self.read(packet)
    count = packet.read_var_int
    recipe_entries = Array(RecipeDisplayEntry).new(count.to_i32)
    flags_map = Hash(UInt32, UInt8).new
    parse_error = nil
    count.times do |i|
      break if parse_error
      begin
        entry = RecipeDisplayEntry.read(packet)
        flags = packet.read_byte
        recipe_entries << entry
        flags_map[entry.id] = flags
      rescue ex
        parse_error = "entry #{i}/#{count}: #{ex.class}: #{ex.message}"
        Log.warn { "RecipeBookAdd: failed to parse #{parse_error}" }
      end
    end
    replace = parse_error ? false : packet.read_bool
    pkt = self.new(recipe_entries, flags_map, replace)
    pkt.parse_error = parse_error
    pkt.expected_count = count
    pkt
  end

  def callback(client)
    client.recipe_registry.add(recipe_entries, replace?)
    if error = parse_error
      client.recipe_registry.record_parse_error(error, expected_count)
    end
    Log.debug { "RecipeBookAdd: #{recipe_entries.size}/#{expected_count} recipes, replace=#{replace?}" }
  end
end
