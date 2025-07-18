require "../spec_helper"

Spectator.describe Rosegold::Packets::ProtocolData do
  describe "protocol data lookup system" do
    it "provides packet ID lookup for LOGIN state packets" do
      # LoginStart should be 0x00 across all versions
      expect(Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 758_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 767_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 771_u32)).to eq(0x00_u8)
    end

    it "provides packet ID lookup for PLAY state packets with version differences" do
      # KeepAlive packet changes between versions
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "keep_alive", 758_u32)).to eq(0x0F_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "keep_alive", 767_u32)).to eq(0x12_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "keep_alive", 771_u32)).to eq(0x12_u8)

      # PlayerPosition packet also changes
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "player_position", 758_u32)).to eq(0x11_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "player_position", 767_u32)).to eq(0x14_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "player_position", 771_u32)).to eq(0x14_u8)
    end

    it "provides packet ID lookup for HANDSHAKING state packets" do
      # Handshake should be 0x00 across all versions
      expect(Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 758_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 767_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 771_u32)).to eq(0x00_u8)
    end

    it "provides packet ID lookup for STATUS state packets" do
      # Status packets should be 0x00 and 0x01 across all versions
      expect(Rosegold::Packets::ProtocolData.get_packet_id("STATUS", "serverbound", "status_request", 758_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("STATUS", "serverbound", "status_ping", 758_u32)).to eq(0x01_u8)
    end

    it "returns nil for unknown packets" do
      expect(Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "unknown_packet", 758_u32)).to be_nil
    end

    it "returns nil for unknown states" do
      expect(Rosegold::Packets::ProtocolData.get_packet_id("UNKNOWN", "serverbound", "login_start", 758_u32)).to be_nil
    end

    it "returns nil for unknown protocols" do
      expect(Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 999_u32)).to be_nil
    end

    it "is case insensitive for state names" do
      expect(Rosegold::Packets::ProtocolData.get_packet_id("login", "serverbound", "login_start", 758_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("Login", "serverbound", "login_start", 758_u32)).to eq(0x00_u8)
      expect(Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 758_u32)).to eq(0x00_u8)
    end
  end

  describe "protocol data validation" do
    it "ensures critical packets have different IDs between protocol 758 and 767" do
      # These are the packets that actually changed between MC 1.18 and 1.21
      chat_758 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "chat_message", 758_u32)
      chat_767 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "chat_message", 767_u32)
      expect(chat_758).to_not eq(chat_767)

      keep_alive_758 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "keep_alive", 758_u32)
      keep_alive_767 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "keep_alive", 767_u32)
      expect(keep_alive_758).to_not eq(keep_alive_767)

      player_pos_758 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "player_position", 758_u32)
      player_pos_767 = Rosegold::Packets::ProtocolData.get_packet_id("PLAY", "serverbound", "player_position", 767_u32)
      expect(player_pos_758).to_not eq(player_pos_767)
    end

    it "ensures stable packets have same IDs across protocols" do
      # These packets should remain the same
      login_758 = Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 758_u32)
      login_767 = Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 767_u32)
      login_771 = Rosegold::Packets::ProtocolData.get_packet_id("LOGIN", "serverbound", "login_start", 771_u32)
      expect(login_758).to eq(login_767)
      expect(login_767).to eq(login_771)

      handshake_758 = Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 758_u32)
      handshake_767 = Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 767_u32)
      handshake_771 = Rosegold::Packets::ProtocolData.get_packet_id("HANDSHAKING", "serverbound", "handshake", 771_u32)
      expect(handshake_758).to eq(handshake_767)
      expect(handshake_767).to eq(handshake_771)
    end
  end
end
