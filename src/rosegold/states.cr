class Rosegold::State::Status
  def self.[](packet_id)
    case packet_id
    when 0x00
      Clientbound::Status
    else
      raise "Unknown packet id: #{packet_id} for Status: Rosegold::State::Status"
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
      Clientbound::LoginDisconnect
    when 0x01
      Clientbound::EncryptionRequest
    when 0x02
      Clientbound::LoginSuccess
    when 0x03
      Clientbound::SetCompression
    when 0x04
      Clientbound::LoginPluginRequest
    else
      raise "Unknown packet id: #{packet_id} for Status: Rosegold::State::Login"
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
    when 0x12
      # TODO: Clientbound::DeclareCommands
    when 0x18
      # TODO: Clientbound::PluginMessage
    when 0x26
      Clientbound::JoinGame
    when 0x32
      # TODO: Clientbound::PlayerAbilities
    when 0x38
      Clientbound::PlayerPositionAndLook
    when 0x39
      # TODO: Clientbound::UnlockRecipes
    when 0x48
      # TODO: Clientbound::HeldItemChange
    when 0x55
      # TODO: Clientbound::Teams
    when 0x66
      # TODO: Clientbound::DeclareRecipes
    when 0x67
      # TODO: Clientbound::Tags
    when 0x1b
      # TODO: Clientbound::EntityAction
    when 0x0e
      Clientbound::ChangeDifficulty
    else
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for Status: Rosegold::State::Play"
    end
  end

  def [](packet_id)
    self.class[packet_id]
  end
end
