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

class Rosegold::State::Disconnected
  def self.[](packet_id)
    nil
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
  MAP = {
    0x1a => Clientbound::Disconnect,
    0x26 => Clientbound::JoinGame,
    0x3d => Clientbound::Respawn,
    0x38 => Clientbound::PlayerPositionAndLook,

    0x21 => Clientbound::KeepAlive,
    0x30 => Clientbound::Ping,

    # blocks
    0x22 => Clientbound::ChunkData,
    0x1d => Clientbound::UnloadChunk,
    0x0c => Clientbound::BlockChange,
    0x3f => Clientbound::MultiBlockChange,
    # 0x1c => Clientbound::Explosion, # TODO change blocks, update velocity

    # inventory
    0x48 => Clientbound::HeldItemChange,
    # 0x2e => Clientbound::OpenWindow,
    # 0x13 => Clientbound::CloseWindow,
    # 0x14 => Clientbound::WindowItems,
    # 0x16 => Clientbound::SetSlot,
    # 0x66 => Clientbound::DeclareRecipes,

    0x0f => Clientbound::Chat,
    # 0x36 => Clientbound::PlayerInfo,
    # 0x0d => Clientbound::BossBar,
    # 0x41 => Clientbound::ActionBar,
    # 0x59 => Clientbound::TimeUpdate,
    # 0x5f => Clientbound::PlayerListHeaderAndFooter,
  }

  def self.[](packet_id)
    MAP[packet_id]?
  end

  def [](packet_id)
    self.class[packet_id]
  end
end
