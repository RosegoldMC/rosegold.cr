require "../spec_helper"

Spectator.describe "Minecraft 26.3 protocol registration" do
  after_each { Rosegold::Client.reset_protocol_version! }

  it "keeps every existing protocol enabled alongside 777" do
    expect(Rosegold::Client::SUPPORTED_PROTOCOLS.to_a).to eq([772_u32, 773_u32, 774_u32, 775_u32, 776_u32, 777_u32])
    expect(Rosegold::Client::LATEST_PROTOCOL).to eq(777_u32)
  end

  it "registers shifted configuration packets after post effects" do
    state = Rosegold::ProtocolState::CONFIGURATION
    expect(state.get_clientbound_packet(0x0F_u32, 777_u32)).to eq(Rosegold::Clientbound::KnownPacks)
    expect(state.get_clientbound_packet(0x03_u32, 777_u32)).to eq(Rosegold::Clientbound::FinishConfiguration)
  end

  it "registers play packets on both sides of the inserted packets" do
    state = Rosegold::ProtocolState::PLAY
    expect(state.get_clientbound_packet(0x26_u32, 777_u32)).to eq(Rosegold::Clientbound::UnloadChunk)
    expect(state.get_clientbound_packet(0x49_u32, 777_u32)).to eq(Rosegold::Clientbound::SynchronizePlayerPosition)
    expect(state.get_clientbound_packet(0x65_u32, 777_u32)).to eq(Rosegold::Clientbound::SetEntityData)
    expect(state.get_clientbound_packet(0x86_u32, 777_u32)).to eq(Rosegold::Clientbound::UpdateAttributes)
    expect(state.get_serverbound_packet(0x42_u32, 777_u32)).to eq(Rosegold::Serverbound::PlayerBlockPlacement)
  end

  it "forwards spectator packets using the 26.3 registry" do
    packets = Rosegold::Spectate::Server.forwarded_packets(777_u32)
    expect(packets[0x65_u32]).to eq("set_entity_data")
    expect(packets[0x86_u32]).to eq("update_attributes")
    expect(packets[0x77_u32]).to eq("sound")
  end

  it "reads and preserves the new cushion dye metadata" do
    Rosegold::Client.protocol_version = 777_u32
    payload = Bytes[0x2A, 0x08, 0x2B, 0x0E, 0xFF]
    io = Minecraft::IO::Memory.new(payload)
    packet = Rosegold::Clientbound::SetEntityData.read(io)
    expect(io.pos).to eq(payload.size)
    expect(packet.entries.first.value).to eq(14_u32)
    expect(packet.write).to eq(Bytes[0x65] + payload)
  end
end
