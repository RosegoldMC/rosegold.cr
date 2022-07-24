require "../spec_helper"

Spectator.describe Rosegold::Physics do
  it "should fall due to gravity" do
    Rosegold::Client.new("localhost", 25565).start do |client|
      sleep 5
      client.queue_packet Rosegold::Serverbound::Chat.new "/tp 1 -58 1"
      sleep 1
      expect(client.player.feet).to eq(Rosegold::Vec3d.new(1.5, -60, 1.5))
    end
  end
end
