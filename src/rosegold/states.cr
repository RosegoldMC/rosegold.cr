class Rosegold::State::Status
  def self.[](packet_id)
    case packet_id
    when 0x00
      Clientbound::Status
    else
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for Status: Rosegold::State::Status"
    end
  end

  def [](packet_id)
    self.class[packet_id]
  end
end

class Rosegold::State::Login
  def self.[](packet_id)
    case packet_id
    when 0x00
      Clientbound::Disconnect
    when 0x01
      Clientbound::EncryptionRequest
    when 0x02
      Clientbound::LoginSuccess
    when 0x03
      Clientbound::SetCompression
    when 0x04
      Clientbound::LoginPluginRequest
    else
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for Status: Rosegold::State::Login"
    end
  end

  def [](packet_id)
    self.class[packet_id]
  end
end

# https://wiki.vg/index.php?title=Protocol&oldid=17499
class Rosegold::State::Play
  def self.[](packet_id)
    case packet_id
    # when 0x23
    when 0x26
      Clientbound::JoinGame
    else
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for Status: Rosegold::State::Play"
    end
  end

  def [](packet_id)
    self.class[packet_id]
  end
end
