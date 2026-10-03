require "../../spec_helper"

Spectator.describe Rosegold::Clientbound::GameEvent do
  it "updates the local player's game mode when the server changes it" do
    client = Rosegold::Client.new("localhost", 25565,
      offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "gamemodetest"})

    Rosegold::Clientbound::GameEvent.change_gamemode(1).callback(client)
    expect(client.player.gamemode).to eq(1_i8)
    Rosegold::Clientbound::GameEvent.change_gamemode(0).callback(client)
    expect(client.player.gamemode).to eq(0_i8)
  end
end
