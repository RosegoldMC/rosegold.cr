require "../packet"

# MC 26.1+: sends game rule values as a map
class Rosegold::Clientbound::GameRuleValues < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    775_u32 => 0x27_u32, # MC 26.1
  })

  property rules : Hash(String, String)

  def initialize(@rules = Hash(String, String).new); end

  def self.read(packet)
    count = packet.read_var_int
    rules = Hash(String, String).new
    count.times do
      key = packet.read_var_string
      value = packet.read_var_string
      rules[key] = value
    end
    self.new(rules)
  end

  def write : Bytes
    Bytes.empty
  end

  def callback(client)
    Log.debug { "GameRuleValues: #{rules.size} rules" }
  end
end
