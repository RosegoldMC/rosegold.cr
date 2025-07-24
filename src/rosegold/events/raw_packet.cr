class Rosegold::Event::RawPacket < Rosegold::Event
  getter bytes : Bytes

  def initialize(@bytes); end
end
