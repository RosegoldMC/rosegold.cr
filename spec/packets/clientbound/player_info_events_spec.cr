require "../../spec_helper"

Spectator.describe "Player join/leave events" do
  after_each { Rosegold::Client.reset_protocol_version! }

  let(client) { Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "tester"}) }

  it "emits PlayerJoined when a new player is added to the list" do
    uuid = UUID.random
    received = [] of Rosegold::Event::PlayerJoined
    client.on(Rosegold::Event::PlayerJoined) { |event| received << event }

    Rosegold::Clientbound::PlayerInfoUpdate.add_player(uuid, "Alice").callback(client)

    expect(received.size).to eq(1)
    expect(received.first.uuid).to eq(uuid)
    expect(received.first.name).to eq("Alice")
    expect(client.player_list[uuid].name).to eq("Alice")
  end

  it "does not re-emit PlayerJoined for subsequent updates to the same player" do
    uuid = UUID.random
    received = [] of Rosegold::Event::PlayerJoined
    client.on(Rosegold::Event::PlayerJoined) { |event| received << event }

    Rosegold::Clientbound::PlayerInfoUpdate.add_player(uuid, "Alice").callback(client)

    latency_only = Rosegold::Clientbound::PlayerInfoUpdate.new(
      Rosegold::Clientbound::PlayerInfoUpdate::UPDATE_LATENCY,
      [Rosegold::Clientbound::PlayerInfoUpdate::PlayerEntry.new(uuid: uuid, latency: 99_i32)]
    )
    latency_only.callback(client)

    Rosegold::Clientbound::PlayerInfoUpdate.add_player(uuid, "Alice").callback(client)

    expect(received.size).to eq(1)
  end

  it "emits PlayerLeft when a player is removed and includes the removed entry" do
    uuid = UUID.random
    Rosegold::Clientbound::PlayerInfoUpdate.add_player(uuid, "Bob").callback(client)

    received = [] of Rosegold::Event::PlayerLeft
    client.on(Rosegold::Event::PlayerLeft) { |event| received << event }

    Rosegold::Clientbound::PlayerInfoRemove.new([uuid]).callback(client)

    expect(received.size).to eq(1)
    expect(received.first.uuid).to eq(uuid)
    expect(received.first.name).to eq("Bob")
    expect(client.player_list[uuid]?).to be_nil
  end

  it "does not emit PlayerLeft for an unknown uuid" do
    received = [] of Rosegold::Event::PlayerLeft
    client.on(Rosegold::Event::PlayerLeft) { |event| received << event }

    Rosegold::Clientbound::PlayerInfoRemove.new([UUID.random]).callback(client)

    expect(received.size).to eq(0)
  end
end
