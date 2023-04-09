abstract class Rosegold::Packet < Rosegold::Event
  def write : Bytes
    raise "Not implemented"
  end

  def callback(client_or_server); end

  def to_s(io)
    io << pretty_inspect(999, " ", 0).sub(/:0x\S+/, "") \
      .gsub(/Rosegold::|Clientbound::|Serverbound::/, "")
  end
end

abstract class Rosegold::Clientbound::Packet < Rosegold::Packet
  class_getter state = Rosegold::ProtocolState::PLAY

  macro inherited
    Rosegold::ProtocolState.register {{@type}}
  end

  def self.new_raw(bytes)
    Rosegold::Clientbound::RawPacket.new bytes
  end
end

abstract class Rosegold::Serverbound::Packet < Rosegold::Packet
  class_getter state = Rosegold::ProtocolState::PLAY

  macro inherited
    Rosegold::ProtocolState.register {{@type}}
  end

  def self.new_raw(bytes)
    Rosegold::Serverbound::RawPacket.new bytes
  end
end

# not decoded eg. because unknown packet_id
module Rosegold::RawPacket
  getter bytes : Bytes

  def packet_id
    bytes[0]
  end

  def write : Bytes
    bytes
  end
end

# not decoded eg. because unknown packet_id
class Rosegold::Clientbound::RawPacket < Rosegold::Clientbound::Packet
  class_getter packet_id = 0xff_u8
  include Rosegold::RawPacket

  def initialize(@bytes); end
end

# not decoded eg. because unknown packet_id
class Rosegold::Serverbound::RawPacket < Rosegold::Serverbound::Packet
  class_getter packet_id = 0xff_u8
  include Rosegold::RawPacket

  def initialize(@bytes); end
end

class Rosegold::ProtocolState
  HANDSHAKING = ProtocolState.new "HANDSHAKING"
  STATUS      = ProtocolState.new "STATUS"
  LOGIN       = ProtocolState.new "LOGIN"
  PLAY        = ProtocolState.new "PLAY"

  getter name : String
  getter clientbound = Hash(UInt8, Clientbound::Packet.class).new
  getter serverbound = Hash(UInt8, Serverbound::Packet.class).new

  def initialize(@name)
  end

  def self.register(packet : Packet.class)
    packet.state.register packet
  end

  def register(packet : Clientbound::Packet.class)
    raise "Clientbound packet #{packet.packet_id} already registered to #{name}, cannot register #{packet}" if clientbound[packet.packet_id]?
    clientbound[packet.packet_id] = packet
  end

  def register(packet : Serverbound::Packet.class)
    raise "Serverbound packet #{packet.packet_id} already registered to #{name}, cannot register #{packet}" if serverbound[packet.packet_id]?
    serverbound[packet.packet_id] = packet
  end
end
