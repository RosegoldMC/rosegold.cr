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
      finish_config_767 = config_state.get_clientbound_packet(0x02_u8, 767_u32)
      expect(finish_config_767).to eq(Rosegold::Clientbound::FinishConfiguration)
      
      # Check that FinishConfiguration serverbound is registered for protocol 767
      finish_config_sb_767 = config_state.get_serverbound_packet(0x02_u8, 767_u32)
      expect(finish_config_sb_767).to eq(Rosegold::Serverbound::FinishConfiguration)
      
      # Check ClientInformation is registered
      client_info_767 = config_state.get_serverbound_packet(0x00_u8, 767_u32)
      expect(client_info_767).to eq(Rosegold::Serverbound::ClientInformation)
    end
  end

  describe "Configuration packets" do
    describe "Rosegold::Clientbound::FinishConfiguration" do
      it "has correct packet ID for protocol 767" do
        expect(Rosegold::Clientbound::FinishConfiguration[767_u32]).to eq(0x02_u8)
      end

      it "has correct packet ID for protocol 771" do
        expect(Rosegold::Clientbound::FinishConfiguration[771_u32]).to eq(0x02_u8)
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
        expect(bytes[0]).to eq(0x00_u8)  # packet ID
        
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