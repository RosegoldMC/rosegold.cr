require "../../spec_helper"

class ResourcePackPushMockClient
  property resource_pack_response : Symbol = :loaded
  property sent_packets : Array(Rosegold::Packet) = [] of Rosegold::Packet

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::ResourcePackPush do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "uses packet ID 0x09 for every supported protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Clientbound::ResourcePackPush[protocol]).to eq(0x09_u8)
    end
  end

  it "supports every enabled protocol" do
    PROTOCOLS.each do |protocol|
      expect(Rosegold::Clientbound::ResourcePackPush.supports_protocol?(protocol)).to be_true
    end
    expect(Rosegold::Clientbound::ResourcePackPush.supports_protocol?(999_u32)).to be_false
  end

  it "belongs to CONFIGURATION state" do
    expect(Rosegold::Clientbound::ResourcePackPush.state).to eq(Rosegold::ProtocolState::CONFIGURATION)
  end

  it "is registered in CONFIGURATION state" do
    config_state = Rosegold::ProtocolState::CONFIGURATION
    expect(config_state.get_clientbound_packet(0x09_u8, 772_u32)).to eq(Rosegold::Clientbound::ResourcePackPush)
  end

  describe "round-trip serialization" do
    it "round-trips without a prompt" do
      id = UUID.new("12345678-1234-5678-9012-123456789012")
      packet = Rosegold::Clientbound::ResourcePackPush.new(id, "https://example.com/pack.zip", "a" * 40, true, nil)
      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read = Rosegold::Clientbound::ResourcePackPush.read(io)

      expect(read.id).to eq(id)
      expect(read.url).to eq("https://example.com/pack.zip")
      expect(read.hash).to eq("a" * 40)
      expect(read.forced?).to be_true
      expect(read.prompt).to be_nil
    end

    it "round-trips with a prompt" do
      id = UUID.new("12345678-1234-5678-9012-123456789012")
      prompt = Rosegold::TextComponent.new("Please install this pack")
      packet = Rosegold::Clientbound::ResourcePackPush.new(id, "https://example.com/pack.zip", "", false, prompt)
      io = Minecraft::IO::Memory.new(packet.write)
      io.read_byte
      read = Rosegold::Clientbound::ResourcePackPush.read(io)

      expect(read.forced?).to be_false
      expect(read.prompt.try(&.text)).to eq("Please install this pack")
    end
  end

  describe ".response_actions" do
    it "declines with a single Declined response" do
      expect(Rosegold::Clientbound::ResourcePackPush.response_actions(:decline)).to eq([
        Rosegold::Serverbound::ResourcePackResponse::Action::Declined,
      ])
    end

    it "accepts and reports successful load by default" do
      expect(Rosegold::Clientbound::ResourcePackPush.response_actions(:loaded)).to eq([
        Rosegold::Serverbound::ResourcePackResponse::Action::Accepted,
        Rosegold::Serverbound::ResourcePackResponse::Action::SuccessfullyLoaded,
      ])
    end
  end

  describe "callback" do
    it "sends accepted then successfully_loaded when not declining" do
      id = UUID.new("12345678-1234-5678-9012-123456789012")
      mock_client = ResourcePackPushMockClient.new
      packet = Rosegold::Clientbound::ResourcePackPush.new(id, "https://example.com/pack.zip", "a" * 40, true, nil)

      packet.callback(mock_client)

      responses = mock_client.sent_packets.map(&.as(Rosegold::Serverbound::ResourcePackResponse).action)
      expect(responses).to eq([
        Rosegold::Serverbound::ResourcePackResponse::Action::Accepted,
        Rosegold::Serverbound::ResourcePackResponse::Action::SuccessfullyLoaded,
      ])
      expect(mock_client.sent_packets.map(&.as(Rosegold::Serverbound::ResourcePackResponse).id)).to eq([id, id])
    end

    it "sends a single declined response when configured to decline" do
      id = UUID.new("12345678-1234-5678-9012-123456789012")
      mock_client = ResourcePackPushMockClient.new
      mock_client.resource_pack_response = :decline
      packet = Rosegold::Clientbound::ResourcePackPush.new(id, "https://example.com/pack.zip", "a" * 40, true, nil)

      packet.callback(mock_client)

      responses = mock_client.sent_packets.map(&.as(Rosegold::Serverbound::ResourcePackResponse).action)
      expect(responses).to eq([Rosegold::Serverbound::ResourcePackResponse::Action::Declined])
    end
  end
end
