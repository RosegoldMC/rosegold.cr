class Rosegold::State::Status
  def self.[](packet_id)
    case packet_id
    when 0x00
      Clientbound::Status
    else
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for State::Status"
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
      raise "Unknown packet id: 0x#{Bytes[packet_id].hexstring} for State::Login"
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
    # connection
    when 0x1a; Clientbound::Disconnect
    when 0x26; Clientbound::JoinGame
    when 0x21; Clientbound::KeepAlive
    when 0x30; Clientbound::Ping
      # player state
    when 0x38; Clientbound::PlayerPositionAndLook
    when 0x3d; nil # TODO: Clientbound::Respawn
    when 0x52; Clientbound::UpdateHealth
      # physics
    when 0x22; Clientbound::ChunkData
    when 0x1d; Clientbound::UnloadChunk
    when 0x0c; nil # TODO: Clientbound::BlockChange
    when 0x3f; nil # TODO: Clientbound::MultiBlockChange
    # inventory
    when 0x48; nil # TODO: Clientbound::HeldItemChange
    when 0x2e; nil # TODO: Clientbound::OpenWindow
    when 0x13; nil # TODO: Clientbound::CloseWindow
    when 0x14; nil # TODO: Clientbound::WindowItems
    when 0x16; nil # TODO: Clientbound::SetSlot
    when 0x66; nil # TODO: Clientbound::DeclareRecipes
    # botting
    when 0x0f; Clientbound::Chat
    when 0x36; nil # TODO: Clientbound::PlayerInfo # tab list
    when 0x0d; nil # TODO: Clientbound::BossBar
    when 0x41; nil # TODO: Clientbound::ActionBar # text above hotbar
    when 0x59; nil # Time Update # to measure TPS
    when 0x5f; nil # Player List Header And Footer # to measure TPS
    end
  end

  def [](packet_id)
    self.class[packet_id]
  end
end
