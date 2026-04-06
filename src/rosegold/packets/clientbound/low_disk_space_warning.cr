require "../packet"

# MC 26.1+: empty marker packet for low disk space
class Rosegold::Clientbound::LowDiskSpaceWarning < Rosegold::Clientbound::Packet
  include Rosegold::Packets::ProtocolMapping
  packet_ids({
    775_u32 => 0x32_u32, # MC 26.1
  })

  def initialize; end

  def self.read(packet)
    self.new
  end

  def write : Bytes
    Bytes.empty
  end

  def callback(client)
    Log.warn { "Server reports low disk space" }
  end
end
