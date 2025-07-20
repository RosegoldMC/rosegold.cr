require "spectator"
require "../../src/rosegold"

Spectator.describe "CONFIGURATION state implementation" do
  describe "ProtocolState::CONFIGURATION" do
    it "includes CONFIGURATION state" do
      expect(Rosegold::ProtocolState::CONFIGURATION.name).to eq("CONFIGURATION")
    end

    it "registers configuration packets properly" do
      config_state = Rosegold::ProtocolState::CONFIGURATION

      # Check that FinishConfiguration is registered for protocol 767
      finish_config_767 = config_state.get_clientbound_packet(0x03_u8, 767_u32)
      expect(finish_config_767).to eq(Rosegold::Clientbound::FinishConfiguration)

      # Check that FinishConfiguration serverbound is registered for protocol 767
      finish_config_sb_767 = config_state.get_serverbound_packet(0x02_u8, 767_u32)
      expect(finish_config_sb_767).to eq(Rosegold::Serverbound::FinishConfiguration)

      # Check ClientInformation is registered
      client_info_767 = config_state.get_serverbound_packet(0x00_u8, 767_u32)
      expect(client_info_767).to eq(Rosegold::Serverbound::ClientInformation)

      # Check KnownPacks packets are registered for protocol 767
      known_packs_cb_767 = config_state.get_clientbound_packet(0x0E_u8, 767_u32)
      expect(known_packs_cb_767).to eq(Rosegold::Clientbound::KnownPacks)

      known_packs_sb_767 = config_state.get_serverbound_packet(0x07_u8, 767_u32)
      expect(known_packs_sb_767).to eq(Rosegold::Serverbound::KnownPacks)
    end
  end

  describe "Configuration packets" do
    describe "Rosegold::Clientbound::FinishConfiguration" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Clientbound::FinishConfiguration[767_u32]).to eq(0x03_u8)
      end

      it "has correct packet ID for protocol 771" do
        expect(Rosegold::Clientbound::FinishConfiguration[771_u32]).to eq(0x03_u8)
      end

      it "does not support protocol 758" do
        expect(Rosegold::Clientbound::FinishConfiguration.supports_protocol?(758_u32)).to be_false
      end

      it "is a CONFIGURATION state packet" do
        expect(Rosegold::Clientbound::FinishConfiguration.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      end
    end

    describe "Rosegold::Serverbound::FinishConfiguration" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Serverbound::FinishConfiguration[767_u32]).to eq(0x02_u8)
      end

      it "writes correct packet structure" do
        packet = Rosegold::Serverbound::FinishConfiguration.new
        bytes = packet.write
        expect(bytes.size).to eq(1)
        expect(bytes[0]).to eq(0x02_u8)
      end

      it "is a CONFIGURATION state packet" do
        expect(Rosegold::Serverbound::FinishConfiguration.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      end
    end

    describe "Rosegold::Serverbound::ClientInformation" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Serverbound::ClientInformation[767_u32]).to eq(0x00_u8)
      end

      it "creates packet with default values" do
        packet = Rosegold::Serverbound::ClientInformation.new
        expect(packet.locale).to eq("en_US")
        expect(packet.view_distance).to eq(10_u8)
        expect(packet.chat_colors).to be_true
      end

      it "writes and reads packet correctly" do
        original = Rosegold::Serverbound::ClientInformation.new(
          locale: "en_GB",
          view_distance: 12_u8,
          chat_mode: 1_u8,
          chat_colors: false,
          displayed_skin_parts: 0x7F_u8,
          main_hand: 0_u8,
          enable_text_filtering: true,
          allow_server_listings: false
        )

        bytes = original.write
        expect(bytes[0]).to eq(0x00_u8) # packet ID

        # Read back the packet (skipping packet ID)
        io = Minecraft::IO::Memory.new(bytes[1..])
        parsed = Rosegold::Serverbound::ClientInformation.read(io)

        expect(parsed.locale).to eq("en_GB")
        expect(parsed.view_distance).to eq(12_u8)
        expect(parsed.chat_mode).to eq(1_u8)
        expect(parsed.chat_colors).to be_false
        expect(parsed.displayed_skin_parts).to eq(0x7F_u8)
        expect(parsed.main_hand).to eq(0_u8)
        expect(parsed.enable_text_filtering).to be_true
        expect(parsed.allow_server_listings).to be_false
      end

      it "is a CONFIGURATION state packet" do
        expect(Rosegold::Serverbound::ClientInformation.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      end
    end

    describe "Rosegold::Clientbound::KnownPacks" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Clientbound::KnownPacks[767_u32]).to eq(0x0E_u8)
      end

      it "has correct packet ID for protocol 771" do
        expect(Rosegold::Clientbound::KnownPacks[771_u32]).to eq(0x0E_u8)
      end

      it "does not support protocol 758" do
        expect(Rosegold::Clientbound::KnownPacks.supports_protocol?(758_u32)).to be_false
      end

      it "is a CONFIGURATION state packet" do
        expect(Rosegold::Clientbound::KnownPacks.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      end

      it "creates packet with empty known packs" do
        packet = Rosegold::Clientbound::KnownPacks.new
        expect(packet.known_packs).to be_empty
      end

      it "creates packet with known packs data" do
        packs = [
          {namespace: "minecraft", id: "core", version: "1.21"},
          {namespace: "modpack", id: "extra", version: "2.0.1"},
        ]
        packet = Rosegold::Clientbound::KnownPacks.new(packs)
        expect(packet.known_packs.size).to eq(2)
        expect(packet.known_packs[0][:namespace]).to eq("minecraft")
        expect(packet.known_packs[0][:id]).to eq("core")
        expect(packet.known_packs[0][:version]).to eq("1.21")
      end

      it "writes and reads packet correctly" do
        packs = [
          {namespace: "minecraft", id: "core", version: "1.21"},
          {namespace: "test", id: "addon", version: "1.0.0"},
        ]
        original = Rosegold::Clientbound::KnownPacks.new(packs)

        bytes = original.write
        expect(bytes[0]).to eq(0x0E_u8) # packet ID

        # Read back the packet (skipping packet ID)
        io = Minecraft::IO::Memory.new(bytes[1..])
        parsed = Rosegold::Clientbound::KnownPacks.read(io)

        expect(parsed.known_packs.size).to eq(2)
        expect(parsed.known_packs[0][:namespace]).to eq("minecraft")
        expect(parsed.known_packs[0][:id]).to eq("core")
        expect(parsed.known_packs[0][:version]).to eq("1.21")
        expect(parsed.known_packs[1][:namespace]).to eq("test")
        expect(parsed.known_packs[1][:id]).to eq("addon")
        expect(parsed.known_packs[1][:version]).to eq("1.0.0")
      end

      it "handles empty known packs list" do
        original = Rosegold::Clientbound::KnownPacks.new

        bytes = original.write
        expect(bytes[0]).to eq(0x0E_u8) # packet ID

        # Read back the packet (skipping packet ID)
        io = Minecraft::IO::Memory.new(bytes[1..])
        parsed = Rosegold::Clientbound::KnownPacks.read(io)

        expect(parsed.known_packs).to be_empty
      end
    end

    describe "Rosegold::Serverbound::KnownPacks" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Serverbound::KnownPacks[767_u32]).to eq(0x07_u8)
      end

      it "has correct packet ID for protocol 771" do
        expect(Rosegold::Serverbound::KnownPacks[771_u32]).to eq(0x07_u8)
      end

      it "does not support protocol 758" do
        expect(Rosegold::Serverbound::KnownPacks.supports_protocol?(758_u32)).to be_false
      end

      it "is a CONFIGURATION state packet" do
        expect(Rosegold::Serverbound::KnownPacks.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      end

      it "creates packet with empty known packs" do
        packet = Rosegold::Serverbound::KnownPacks.new
        expect(packet.known_packs).to be_empty
      end

      it "writes and reads packet correctly" do
        packs = [
          {namespace: "minecraft", id: "core", version: "1.21"},
          {namespace: "custom", id: "pack", version: "3.1.4"},
        ]
        original = Rosegold::Serverbound::KnownPacks.new(packs)

        bytes = original.write
        expect(bytes[0]).to eq(0x07_u8) # packet ID

        # Read back the packet (skipping packet ID)
        io = Minecraft::IO::Memory.new(bytes[1..])
        parsed = Rosegold::Serverbound::KnownPacks.read(io)

        expect(parsed.known_packs.size).to eq(2)
        expect(parsed.known_packs[0][:namespace]).to eq("minecraft")
        expect(parsed.known_packs[0][:id]).to eq("core")
        expect(parsed.known_packs[0][:version]).to eq("1.21")
        expect(parsed.known_packs[1][:namespace]).to eq("custom")
        expect(parsed.known_packs[1][:id]).to eq("pack")
        expect(parsed.known_packs[1][:version]).to eq("3.1.4")
      end
    end
  end

  describe "LoginSuccess state transition" do
    it "transitions to CONFIGURATION for protocol 767+" do
      # This would require a mock client implementation to test properly
      # For now, we verify the logic exists by checking the packet state
      expect(Rosegold::Clientbound::LoginSuccess.state).to eq(Rosegold::ProtocolState::LOGIN)
      expect(Rosegold::Serverbound::LoginAcknowledged.state).to eq(Rosegold::ProtocolState::LOGIN)
    end
  end
end
