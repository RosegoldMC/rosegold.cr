require "../spec_helper"

private def test_client
  Rosegold::Client.new("localhost", 25565, offline: {uuid: "00000000-0000-0000-0000-000000000000", username: "eventtest"})
end

Spectator.describe Rosegold::Event::ContainerOpened do
  let(:client) { test_client }
  let(:menu) { Rosegold::ChestMenu.new(client, 1_u8, Rosegold::Chat.new("Test Chest"), rows: 3) }

  it "stores window_type" do
    event = Rosegold::Event::ContainerOpened.new(2_u32, "Chest", menu)
    expect(event.window_type).to eq 2_u32
  end

  it "stores title" do
    event = Rosegold::Event::ContainerOpened.new(2_u32, "Chest", menu)
    expect(event.title).to eq "Chest"
  end

  it "stores menu" do
    event = Rosegold::Event::ContainerOpened.new(2_u32, "Chest", menu)
    expect(event.menu).to be menu
  end
end
