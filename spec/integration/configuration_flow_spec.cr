require "spectator"
require "../../src/rosegold"

# Mock client for testing state transitions
class MockClient
  property protocol_version : UInt32
  property current_protocol_state : Rosegold::ProtocolState
  property player : Rosegold::Player = Rosegold::Player.new
  property sent_packets : Array(Rosegold::Packet) = [] of Rosegold::Packet

  def initialize(@protocol_version, @current_protocol_state = Rosegold::ProtocolState::HANDSHAKING)
  end

  def set_protocol_state(state : Rosegold::ProtocolState)
    @current_protocol_state = state
  end

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe "Protocol state transitions for MC 1.21+ configuration" do
  describe "LoginSuccess callback behavior" do
    it "transitions MC 1.18 (protocol 758) directly to PLAY state" do
      mock_client = MockClient.new(758_u32, Rosegold::ProtocolState::LOGIN)

      # Create LoginSuccess packet and trigger callback
      login_success = Rosegold::Clientbound::LoginSuccess.new(
        UUID.new("12345678-1234-5678-9012-123456789012"),
        "testuser"
      )

      login_success.callback(mock_client)

      # For MC 1.18, should go directly to PLAY
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::PLAY)
      expect(mock_client.player.username).to eq("testuser")

      # Should not send LoginAcknowledged for MC 1.18
      login_ack_packets = mock_client.sent_packets.select(Rosegold::Serverbound::LoginAcknowledged)
      expect(login_ack_packets.size).to eq(0)
    end

    it "transitions MC 1.21.8 (protocol 772) to CONFIGURATION state" do
      mock_client = MockClient.new(772_u32, Rosegold::ProtocolState::LOGIN)

      # Create LoginSuccess packet and trigger callback
      login_success = Rosegold::Clientbound::LoginSuccess.new(
        UUID.new("12345678-1234-5678-9012-123456789012"),
        "testuser"
      )

      login_success.callback(mock_client)

      # For MC 1.21+, should go to CONFIGURATION
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      expect(mock_client.player.username).to eq("testuser")

      # Should send LoginAcknowledged for MC 1.21+
      login_ack_packets = mock_client.sent_packets.select(Rosegold::Serverbound::LoginAcknowledged)
      expect(login_ack_packets.size).to eq(1)
    end

    it "transitions MC 1.21.8 (protocol 772) to CONFIGURATION state" do
      mock_client = MockClient.new(772_u32, Rosegold::ProtocolState::LOGIN)

      # Create LoginSuccess packet and trigger callback
      login_success = Rosegold::Clientbound::LoginSuccess.new(
        UUID.new("12345678-1234-5678-9012-123456789012"),
        "testuser"
      )

      login_success.callback(mock_client)

      # For MC 1.21.6, should go to CONFIGURATION
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::CONFIGURATION)

      # Should send LoginAcknowledged for MC 1.21.6
      login_ack_packets = mock_client.sent_packets.select(Rosegold::Serverbound::LoginAcknowledged)
      expect(login_ack_packets.size).to eq(1)
    end
  end

  describe "LoginAcknowledged callback behavior" do
    it "sends ClientInformation packet automatically in CONFIGURATION state" do
      mock_client = MockClient.new(772_u32, Rosegold::ProtocolState::CONFIGURATION)

      # Create LoginAcknowledged packet and trigger callback
      login_ack = Rosegold::Serverbound::LoginAcknowledged.new
      login_ack.callback(mock_client)

      # Should send ClientInformation packet
      client_info_packets = mock_client.sent_packets.select(Rosegold::Serverbound::ClientInformation)
      expect(client_info_packets.size).to eq(1)
    end
  end

  describe "FinishConfiguration callback behavior" do
    it "sends FinishConfiguration response and transitions to PLAY state" do
      mock_client = MockClient.new(772_u32, Rosegold::ProtocolState::CONFIGURATION)

      # Create FinishConfiguration clientbound packet and trigger callback
      finish_config = Rosegold::Clientbound::FinishConfiguration.new
      finish_config.callback(mock_client)

      # Should send FinishConfiguration serverbound response
      finish_config_packets = mock_client.sent_packets.select(Rosegold::Serverbound::FinishConfiguration)
      expect(finish_config_packets.size).to eq(1)

      # Should transition to PLAY state
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::PLAY)
    end
  end

  describe "Complete configuration flow simulation for MC 1.21+" do
    it "follows correct state transitions from LOGIN to PLAY via CONFIGURATION" do
      mock_client = MockClient.new(772_u32, Rosegold::ProtocolState::LOGIN)

      # Step 1: LoginSuccess packet moves to CONFIGURATION and sends LoginAcknowledged
      login_success = Rosegold::Clientbound::LoginSuccess.new(
        UUID.new("12345678-1234-5678-9012-123456789012"),
        "testuser"
      )
      login_success.callback(mock_client)

      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::CONFIGURATION)
      login_ack_packets = mock_client.sent_packets.select(Rosegold::Serverbound::LoginAcknowledged)
      expect(login_ack_packets.size).to eq(1)

      # Step 2: LoginAcknowledged callback sends ClientInformation
      login_ack = login_ack_packets.first.as(Rosegold::Serverbound::LoginAcknowledged)
      login_ack.callback(mock_client)

      client_info_packets = mock_client.sent_packets.select(Rosegold::Serverbound::ClientInformation)
      expect(client_info_packets.size).to eq(1)
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::CONFIGURATION)

      # Step 3: Server would send configuration data (RegistryData, UpdateTags, etc.)
      # We can simulate receiving these packets
      registry_data = Rosegold::Clientbound::RegistryData.new("minecraft:dimension_type")
      registry_data.callback(mock_client) # Should log but not change state

      update_tags = Rosegold::Clientbound::UpdateTags.new
      update_tags.callback(mock_client) # Should log but not change state

      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::CONFIGURATION)

      # Step 4: FinishConfiguration completes the configuration phase
      finish_config = Rosegold::Clientbound::FinishConfiguration.new
      finish_config.callback(mock_client)

      # Should send response and transition to PLAY
      finish_config_packets = mock_client.sent_packets.select(Rosegold::Serverbound::FinishConfiguration)
      expect(finish_config_packets.size).to eq(1)
      expect(mock_client.current_protocol_state).to eq(Rosegold::ProtocolState::PLAY)

      # Verify all expected packets were sent in order
      packet_types = mock_client.sent_packets.map(&.class.name)
      expected_order = [
        "Rosegold::Serverbound::LoginAcknowledged",
        "Rosegold::Serverbound::ClientInformation",
        "Rosegold::Serverbound::FinishConfiguration",
      ]
      expect(packet_types).to eq(expected_order)
    end
  end

  describe "Configuration state packet registration" do
    it "properly registers all configuration packets in CONFIGURATION state" do
      config_state = Rosegold::ProtocolState::CONFIGURATION

      # Check clientbound packets for protocol 772
      expect(config_state.get_clientbound_packet(0x03_u8, 772_u32)).to eq(Rosegold::Clientbound::FinishConfiguration)
      expect(config_state.get_clientbound_packet(0x05_u8, 772_u32)).to eq(Rosegold::Clientbound::RegistryData)
      expect(config_state.get_clientbound_packet(0x08_u8, 772_u32)).to eq(Rosegold::Clientbound::UpdateTags)

      # Check serverbound packets for protocol 772
      expect(config_state.get_serverbound_packet(0x00_u8, 772_u32)).to eq(Rosegold::Serverbound::ClientInformation)
      expect(config_state.get_serverbound_packet(0x03_u8, 772_u32)).to eq(Rosegold::Serverbound::FinishConfiguration)
    end
  end
end
