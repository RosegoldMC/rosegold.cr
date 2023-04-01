abstract class Rosegold::Packet
  def write : Bytes
    raise "Not implemented"
  end

  def callback(client_or_server); end
end

abstract class Rosegold::Clientbound::Packet < Rosegold::Packet; end

abstract class Rosegold::Serverbound::Packet < Rosegold::Packet; end

class Rosegold::ProtocolState
  HANDSHAKING = ProtocolState.new
  STATUS      = ProtocolState.new
  LOGIN       = ProtocolState.new
  PLAY        = ProtocolState.new

  getter clientbound = Hash(UInt8, Clientbound::Packet.class).new
  getter serverbound = Hash(UInt8, Serverbound::Packet.class).new

  def register(packet : Packet.class)
    if packet.is_a? Clientbound::Packet.class
      raise "Clientbound packet #{packet.packet_id} already registered" if clientbound[packet.packet_id]?
      clientbound[packet.packet_id] = packet
    elsif packet.is_a? Serverbound::Packet.class
      raise "Serverbound packet #{packet.packet_id} already registered" if serverbound[packet.packet_id]?
      serverbound[packet.packet_id] = packet
    else
      raise "#{packet} is neither Clientbound nor Serverbound"
    end
  end
end
