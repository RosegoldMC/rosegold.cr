require "../../spec_helper"

Spectator.describe "PlayerInfoUpdate Serialization" do
  it "can read PlayerInfoUpdate packet and verify structural consistency" do
    # Set protocol version to match the captured packet
    Rosegold::Client.protocol_version = 772_u32

    # Read the captured PlayerInfoUpdate packet hex data from fixture
    hex_data = File.read(File.join(__DIR__, "../../fixtures/packets/clientbound/player_info_update.hex")).strip
    original_bytes = hex_data.hexbytes

    # Parse the packet - skip packet ID (first byte should be 0x3F)
    io = Minecraft::IO::Memory.new(original_bytes[1..])
    packet = Rosegold::Clientbound::PlayerInfoUpdate.read(io)

    # Verify we can parse the real packet correctly
    expect(packet.actions).to be_a(UInt8)
    expect(packet.players.size).to be > 0

    packet.players.each do |player|
      expect(player.uuid).to be_a(UUID)

      # Verify fields are populated based on action flags
      if (packet.actions & Rosegold::Clientbound::PlayerInfoUpdate::ADD_PLAYER) != 0
        expect(player.name).to_not be_nil
        expect(player.properties).to_not be_nil
      end

      if (packet.actions & Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_GAMEMODE) != 0
        expect(player.gamemode).to_not be_nil
      end

      if (packet.actions & Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LISTED) != 0
        expect(player.listed).to_not be_nil
      end

      if (packet.actions & Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY) != 0
        expect(player.latency).to_not be_nil
      end
    end

    # Write the packet back out and verify size match
    rewritten_bytes = packet.write
    expect(rewritten_bytes.size).to eq(original_bytes.size)

    # Test that we can read our own written packet back
    io2 = Minecraft::IO::Memory.new(rewritten_bytes[1..])
    reparsed_packet = Rosegold::Clientbound::PlayerInfoUpdate.read(io2)

    # Verify essential structural consistency after rewrite
    expect(reparsed_packet.actions).to eq(packet.actions)
    expect(reparsed_packet.players.size).to eq(packet.players.size)

    reparsed_packet.players.zip(packet.players) do |reparsed_player, original_player|
      expect(reparsed_player.uuid).to eq(original_player.uuid)
      expect(reparsed_player.name).to eq(original_player.name)
      expect(reparsed_player.gamemode).to eq(original_player.gamemode)
      expect(reparsed_player.listed).to eq(original_player.listed)
      expect(reparsed_player.latency).to eq(original_player.latency)
    end
  end

  it "can create and serialize PlayerInfoUpdate packet from scratch" do
    Rosegold::Client.protocol_version = 772_u32

    # Create test data for adding a player
    uuid = UUID.random
    name = "TestPlayer"
    actions = Rosegold::Clientbound::PlayerInfoUpdate::ADD_PLAYER |
              Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_GAMEMODE |
              Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LISTED |
              Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY

    properties = [
      Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry::Property.new(
        "textures", "sample_value", "sample_signature"
      ),
    ]

    player = Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(
      uuid: uuid,
      name: name,
      properties: properties,
      gamemode: 1_i32,
      listed: true,
      latency: 50_i32
    )

    # Create packet
    packet = Rosegold::Clientbound::PlayerInfoUpdate.new(actions, [player])

    # Test serialization roundtrip
    written_bytes = packet.write
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::PlayerInfoUpdate.read(io)

    expect(parsed_packet.actions).to eq(actions)
    expect(parsed_packet.players.size).to eq(1)

    parsed_player = parsed_packet.players.first
    expect(parsed_player.uuid).to eq(uuid)
    expect(parsed_player.name).to eq(name)
    expect(parsed_player.gamemode).to eq(1_i32)
    expect(parsed_player.listed).to eq(true)
    expect(parsed_player.latency).to eq(50_i32)
    expect(parsed_player.properties.try(&.size)).to eq(1)
  end

  it "can handle packets with different action combinations" do
    Rosegold::Client.protocol_version = 772_u32

    # Test UPDATE_LATENCY only
    uuid = UUID.random
    actions = Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY

    player = Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(
      uuid: uuid,
      latency: 100_i32
    )

    packet = Rosegold::Clientbound::PlayerInfoUpdate.new(actions, [player])

    # Test serialization roundtrip
    written_bytes = packet.write
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::PlayerInfoUpdate.read(io)

    expect(parsed_packet.actions).to eq(actions)
    expect(parsed_packet.players.size).to eq(1)

    parsed_player = parsed_packet.players.first
    expect(parsed_player.uuid).to eq(uuid)
    expect(parsed_player.name).to be_nil
    expect(parsed_player.gamemode).to be_nil
    expect(parsed_player.listed).to be_nil
    expect(parsed_player.latency).to eq(100_i32)
    expect(parsed_player.properties).to be_nil
  end

  it "can handle multiple players in one packet" do
    Rosegold::Client.protocol_version = 772_u32

    # Create multiple players
    uuid1 = UUID.random
    uuid2 = UUID.random
    actions = Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LISTED

    players = [
      Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(uuid: uuid1, listed: true),
      Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(uuid: uuid2, listed: false),
    ]

    packet = Rosegold::Clientbound::PlayerInfoUpdate.new(actions, players)

    # Test serialization roundtrip
    written_bytes = packet.write
    io = Minecraft::IO::Memory.new(written_bytes[1..])
    parsed_packet = Rosegold::Clientbound::PlayerInfoUpdate.read(io)

    expect(parsed_packet.actions).to eq(actions)
    expect(parsed_packet.players.size).to eq(2)

    expect(parsed_packet.players[0].uuid).to eq(uuid1)
    expect(parsed_packet.players[0].listed).to eq(true)
    expect(parsed_packet.players[1].uuid).to eq(uuid2)
    expect(parsed_packet.players[1].listed).to eq(false)
  end
end
