require "./protocol_mapping"

abstract class Rosegold::Packet < Rosegold::Event
  def write : Bytes
    raise "Not implemented: write #{self}"
  end

  def callback(client_or_server); end

  def to_s(io)
    io << pretty_inspect(999, " ", 0).sub(/:0x\S+/, "").gsub(/Rosegold::/, "")
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

  def packet_id : UInt32
    result = 0_u32
    shift = 0
    bytes.each do |byte|
      result |= ((byte & 0x7F).to_u32) << shift
      return result if byte & 0x80 == 0
      shift += 7
    end
    result
  end

  def write : Bytes
    bytes
  end
end

# not decoded eg. because unknown packet_id
class Rosegold::Clientbound::RawPacket < Rosegold::Clientbound::Packet
  class_getter packet_id = 0xff_u32
  include Rosegold::RawPacket

  def initialize(@bytes); end
end

# not decoded eg. because unknown packet_id
class Rosegold::Serverbound::RawPacket < Rosegold::Serverbound::Packet
  class_getter packet_id = 0xff_u32
  include Rosegold::RawPacket

  def initialize(@bytes); end
end

class Rosegold::ProtocolState
  HANDSHAKING   = ProtocolState.new "HANDSHAKING"
  STATUS        = ProtocolState.new "STATUS"
  LOGIN         = ProtocolState.new "LOGIN"
  CONFIGURATION = ProtocolState.new "CONFIGURATION"
  PLAY          = ProtocolState.new "PLAY"

  getter name : String
  getter clientbound = Hash({UInt32, UInt32}, Clientbound::Packet.class).new
  getter serverbound = Hash({UInt32, UInt32}, Serverbound::Packet.class).new

  def initialize(@name)
  end

  def self.register(packet : Packet.class)
    packet.state.register packet
  end

  def register(packet : Clientbound::Packet.class)
    register_packet_for_protocols(packet, clientbound)
  end

  def register(packet : Serverbound::Packet.class)
    register_packet_for_protocols(packet, serverbound)
  end

  # Register a packet for all its supported protocols
  private def register_packet_for_protocols(packet, registry)
    # Skip RawPacket classes - they are special and shouldn't be registered
    return if packet.name.includes?("RawPacket")

    # All packets should now use protocol-aware system
    unless packet.responds_to?(:supported_protocols)
      raise "Packet #{packet} must use packet_ids macro for protocol-aware support"
    end

    # Register for each supported protocol
    packet.supported_protocols.each do |protocol|
      packet_id = packet[protocol]
      key = {packet_id, protocol}
      if existing = registry[key]?
        raise "Packet {#{packet_id}, #{protocol}} already registered to #{name}, cannot register #{packet} (existing: #{existing})"
      end
      registry[key] = packet
    end
  end

  # Get packet class for specific packet ID and protocol version
  def get_clientbound_packet(packet_id : UInt32, protocol : UInt32)
    clientbound[{packet_id, protocol}]?
  end

  def get_serverbound_packet(packet_id : UInt32, protocol : UInt32)
    serverbound[{packet_id, protocol}]?
  end

  def clientbound_for_protocol(protocol : UInt32) : Hash(UInt32, Clientbound::Packet.class)
    result = Hash(UInt32, Clientbound::Packet.class).new
    clientbound.each do |(packet_id, proto), packet_class|
      if proto == protocol
        result[packet_id] = packet_class
      end
    end
    result
  end

  def serverbound_for_protocol(protocol : UInt32) : Hash(UInt32, Serverbound::Packet.class)
    result = Hash(UInt32, Serverbound::Packet.class).new
    serverbound.each do |(packet_id, proto), packet_class|
      if proto == protocol
        result[packet_id] = packet_class
      end
    end
    result
  end
end
