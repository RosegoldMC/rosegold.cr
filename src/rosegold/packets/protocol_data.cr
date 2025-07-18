# Protocol-specific packet ID data extracted from Minecraft Wiki
# Sources:
# - Protocol 758 (MC 1.18): https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=3024144
# - Protocol 767 (MC 1.21): https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2789623
# - Protocol 771 (MC 1.21.6): https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2772783

module Rosegold::Packets::ProtocolData
  # Serverbound packet IDs for LOGIN state
  LOGIN_SERVERBOUND = {
    # LoginStart packet
    "login_start" => {
      758 => 0x00_u8, # MC 1.18
      767 => 0x00_u8, # MC 1.21
      771 => 0x00_u8, # MC 1.21.6
    },
    # Encryption Response packet
    "encryption_response" => {
      758 => 0x01_u8, # MC 1.18
      767 => 0x01_u8, # MC 1.21
      771 => 0x01_u8, # MC 1.21.6
    },
    # Login Plugin Response packet
    "login_plugin_response" => {
      758 => 0x02_u8, # MC 1.18
      767 => 0x02_u8, # MC 1.21
      771 => 0x02_u8, # MC 1.21.6
    },
  }

  # Serverbound packet IDs for PLAY state
  PLAY_SERVERBOUND = {
    # Chat Message packet
    "chat_message" => {
      758 => 0x03_u8, # MC 1.18
      767 => 0x05_u8, # MC 1.21 - CHANGED!
      771 => 0x05_u8, # MC 1.21.6
    },
    # Keep Alive packet
    "keep_alive" => {
      758 => 0x0F_u8, # MC 1.18
      767 => 0x12_u8, # MC 1.21 - CHANGED!
      771 => 0x12_u8, # MC 1.21.6
    },
    # Player Position packet
    "player_position" => {
      758 => 0x11_u8, # MC 1.18
      767 => 0x14_u8, # MC 1.21 - CHANGED!
      771 => 0x14_u8, # MC 1.21.6
    },
    # Player Position and Look packet
    "player_position_and_look" => {
      758 => 0x12_u8, # MC 1.18
      767 => 0x15_u8, # MC 1.21 - CHANGED!
      771 => 0x15_u8, # MC 1.21.6
    },
    # Player Look packet
    "player_look" => {
      758 => 0x13_u8, # MC 1.18
      767 => 0x16_u8, # MC 1.21 - CHANGED!
      771 => 0x16_u8, # MC 1.21.6
    },
    # Swing Arm packet
    "swing_arm" => {
      758 => 0x2C_u8, # MC 1.18
      767 => 0x2F_u8, # MC 1.21 - CHANGED!
      771 => 0x2F_u8, # MC 1.21.6
    },
    # Use Item packet
    "use_item" => {
      758 => 0x2D_u8, # MC 1.18
      767 => 0x30_u8, # MC 1.21 - CHANGED!
      771 => 0x30_u8, # MC 1.21.6
    },
  }

  # Serverbound packet IDs for HANDSHAKING state
  HANDSHAKING_SERVERBOUND = {
    # Handshake packet
    "handshake" => {
      758 => 0x00_u8, # MC 1.18
      767 => 0x00_u8, # MC 1.21
      771 => 0x00_u8, # MC 1.21.6
    },
  }

  # Serverbound packet IDs for STATUS state
  STATUS_SERVERBOUND = {
    # Status Request packet
    "status_request" => {
      758 => 0x00_u8, # MC 1.18
      767 => 0x00_u8, # MC 1.21
      771 => 0x00_u8, # MC 1.21.6
    },
    # Status Ping packet
    "status_ping" => {
      758 => 0x01_u8, # MC 1.18
      767 => 0x01_u8, # MC 1.21
      771 => 0x01_u8, # MC 1.21.6
    },
  }

  # Helper method to get packet ID for a specific packet name and protocol
  def self.get_packet_id(state : String, direction : String, packet_name : String, protocol : UInt32) : UInt8?
    case state.upcase
    when "LOGIN"
      data = LOGIN_SERVERBOUND[packet_name]?
      data ? data[protocol]? : nil
    when "PLAY"
      data = PLAY_SERVERBOUND[packet_name]?
      data ? data[protocol]? : nil
    when "HANDSHAKING"
      data = HANDSHAKING_SERVERBOUND[packet_name]?
      data ? data[protocol]? : nil
    when "STATUS"
      data = STATUS_SERVERBOUND[packet_name]?
      data ? data[protocol]? : nil
    else
      nil
    end
  end
end
