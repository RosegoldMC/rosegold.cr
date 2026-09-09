require "../../spec_helper"

class ResourcePackPushMockClient
  property resource_pack_response : Symbol = :decline
  property sent_packets = [] of Rosegold::Packet

  def send_packet!(packet : Rosegold::Packet)
    @sent_packets << packet
  end
end

Spectator.describe Rosegold::Clientbound::ResourcePackPush do
  PROTOCOLS = {772_u32, 773_u32, 774_u32, 775_u32, 776_u32}

  it "maps to 0x09 in every supported protocol" do
    PROTOCOLS.each { |protocol| expect(described_class[protocol]).to eq(0x09_u8) }
  end

  it "is registered in CONFIGURATION" do
    expect(Rosegold::ProtocolState::CONFIGURATION.get_clientbound_packet(0x09_u8, 772_u32)).to eq(described_class)
  end

  it "round-trips a prompted pack" do
    id = UUID.new("12345678-1234-5678-9012-123456789012")
    packet = described_class.new(id, "https://example.com/pack.zip", "a" * 40, true, Rosegold::TextComponent.new("Install it"))
    io = Minecraft::IO::Memory.new(packet.write)
    io.read_byte
    read = described_class.read(io)

    expect(read.id).to eq(id)
    expect(read.prompt.try(&.text)).to eq("Install it")
  end

  it "declines by default because it cannot load a pack" do
    expect(Rosegold::Client.new("localhost").resource_pack_response).to eq(:decline)

    client = ResourcePackPushMockClient.new
    described_class.new(UUID.random, "url", "hash", false).callback(client)

    expect(client.sent_packets.map(&.as(Rosegold::Serverbound::ResourcePackResponse).action)).to eq([
      Rosegold::Serverbound::ResourcePackResponse::Action::Declined,
    ])
  end

  it "allows an explicit compatibility-only loaded acknowledgement" do
    client = ResourcePackPushMockClient.new
    client.resource_pack_response = :loaded
    described_class.new(UUID.random, "url", "hash", false).callback(client)

    expect(client.sent_packets.map(&.as(Rosegold::Serverbound::ResourcePackResponse).action)).to eq([
      Rosegold::Serverbound::ResourcePackResponse::Action::Accepted,
      Rosegold::Serverbound::ResourcePackResponse::Action::SuccessfullyLoaded,
    ])
  end
end
